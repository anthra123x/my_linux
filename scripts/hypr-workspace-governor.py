#!/usr/bin/env python3
"""
hypr-workspace-governor.py

Gobernador de recursos de espacios de trabajo para Hyprland.
Garantiza que el consumo de CPU, I/O y memoria del sistema este dedicado
exclusivamente al espacio de trabajo actualmente visible y en foco.

Mecanismo:
1. Conecta al socket de eventos IPC de Hyprland (.socket2.sock).
2. Escucha en tiempo real eventos de workspace, foco, apertura y cierre de ventanas (0% CPU en reposo).
3. Identifica aplicaciones con reproduccion de audio activa via PipeWire / PulseAudio (pactl).
4. Aplica optimizaciones mediante llamadas al sistema del kernel Linux (sin subprocesos lentos):
   - Ventanas en workspace ACTIVO: SCHED_OTHER (prioridad estandar), nice 0, I/O normal.
   - Ventanas en workspace INACTIVO (sin audio): SCHED_IDLE (prioridad ociosa absoluta), nice 19, I/O idle.
   - Ventanas en workspace INACTIVO (con audio): SCHED_OTHER protegido, nice 8 (previene micro-cortes de sonido).
5. Al cerrarse (SIGINT, SIGTERM), restaura todas las aplicaciones a SCHED_OTHER y nice 0.
"""

import os
import sys
import glob
import json
import time
import signal
import socket
import ctypes
import subprocess
from typing import Dict, Set, Tuple

# Constantes del kernel de Linux
SYS_ioprio_set = 251
IOPRIO_WHO_PROCESS = 1
IOPRIO_CLASS_NONE = 0
IOPRIO_CLASS_RT = 1
IOPRIO_CLASS_BE = 2
IOPRIO_CLASS_IDLE = 3

libc = ctypes.CDLL(None)

def set_process_ioprio(pid: int, ioclass: int, iodata: int = 0) -> None:
    """Ajusta la prioridad de entrada/salida (I/O) de un hilo/proceso."""
    try:
        prio = (ioclass << 13) | (iodata & 0x1FFF)
        libc.syscall(SYS_ioprio_set, IOPRIO_WHO_PROCESS, pid, prio)
    except Exception:
        pass

def get_descendant_pids_and_tids(root_pid: int) -> Set[int]:
    """Obtiene el PID raiz, todos sus hilos internos (TIDs) y sus procesos hijos."""
    all_pids: Set[int] = set()
    stack = [root_pid]
    
    while stack:
        curr = stack.pop()
        if curr in all_pids:
            continue
        all_pids.add(curr)
        
        # Hilos en /proc/<pid>/task/
        task_dir = f"/proc/{curr}/task"
        if os.path.isdir(task_dir):
            try:
                for tid_entry in os.listdir(task_dir):
                    tid = int(tid_entry)
                    all_pids.add(tid)
            except Exception:
                pass
                
        # Procesos hijos
        try:
            out = subprocess.check_output(["pgrep", "-P", str(curr)], text=True, stderr=subprocess.DEVNULL)
            for child in out.strip().split():
                c_pid = int(child)
                if c_pid not in all_pids:
                    stack.append(c_pid)
        except Exception:
            pass
            
    return all_pids

def get_audio_pids() -> Set[int]:
    """Devuelve el conjunto de PIDs que estan reproduciendo audio actualmente."""
    audio_pids: Set[int] = set()
    try:
        out = subprocess.check_output(["pactl", "-f", "json", "list", "sink-inputs"], text=True, stderr=subprocess.DEVNULL)
        data = json.loads(out)
        for item in data:
            props = item.get("properties", {})
            pid_str = props.get("application.process.id")
            if pid_str:
                try:
                    audio_pids.add(int(pid_str))
                except ValueError:
                    pass
    except Exception:
        pass
    return audio_pids

class HyprWorkspaceGovernor:
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.active_workspace_id = -1
        self.managed_pids: Set[int] = set()
        self.running = True

    def log(self, msg: str) -> None:
        if self.verbose:
            ts = time.strftime("%Y-%m-%d %H:%M:%S")
            print(f"[{ts}] [governor] {msg}", flush=True)

    def find_socket(self) -> str:
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        pattern = os.path.join(xdg_runtime, "hypr", "*", ".socket2.sock")
        matches = glob.glob(pattern)
        if matches:
            return matches[0]
        # Fallback a signature directa
        his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if his:
            direct = os.path.join(xdg_runtime, "hypr", his, ".socket2.sock")
            if os.path.exists(direct):
                return direct
        raise FileNotFoundError("No se encontro el socket IPC (.socket2.sock) de Hyprland.")

    def get_clients_and_active_workspace(self) -> Tuple[int, list]:
        try:
            ws_out = subprocess.check_output(["hyprctl", "-j", "activeworkspace"], text=True, stderr=subprocess.DEVNULL)
            ws_data = json.loads(ws_out)
            active_ws = ws_data.get("id", 1)
        except Exception:
            active_ws = 1

        try:
            cl_out = subprocess.check_output(["hyprctl", "-j", "clients"], text=True, stderr=subprocess.DEVNULL)
            clients = json.loads(cl_out)
        except Exception:
            clients = []

        return active_ws, clients

    def apply_governor(self) -> None:
        active_ws, clients = self.get_clients_and_active_workspace()
        self.active_workspace_id = active_ws
        audio_pids = get_audio_pids()

        active_root_pids: Set[int] = set()
        inactive_root_pids: Set[int] = set()

        for c in clients:
            pid = c.get("pid")
            if not pid or pid <= 1:
                continue
            ws_id = c.get("workspace", {}).get("id")
            if ws_id == active_ws:
                active_root_pids.add(pid)
            else:
                inactive_root_pids.add(pid)

        # Si un proceso tiene ventanas en ambos espacios, gana el activo
        inactive_root_pids = inactive_root_pids - active_root_pids

        # 1. Expandir a todos los hilos y procesos hijos
        active_all_pids: Set[int] = set()
        for rpid in active_root_pids:
            active_all_pids.update(get_descendant_pids_and_tids(rpid))

        inactive_all_pids: Set[int] = set()
        for rpid in inactive_root_pids:
            inactive_all_pids.update(get_descendant_pids_and_tids(rpid))

        # Evitar tocar PIDs activos si quedaron compartidos
        inactive_all_pids = inactive_all_pids - active_all_pids

        # Verificar si algun proceso inactivo o descendiente tiene audio
        audio_active_descendants: Set[int] = set()
        for apid in audio_pids:
            audio_active_descendants.update(get_descendant_pids_and_tids(apid))

        # 2. Aplicar prioridad normal a activos
        for pid in active_all_pids:
            self.managed_pids.add(pid)
            try:
                os.sched_setscheduler(pid, os.SCHED_OTHER, os.sched_param(0))
                os.setpriority(os.PRIO_PROCESS, pid, 0)
                set_process_ioprio(pid, IOPRIO_CLASS_BE, 0)
            except (ProcessLookupError, PermissionError):
                pass

        # 3. Aplicar prioridad de reposo a inactivos
        throttled_count = 0
        protected_count = 0

        for pid in inactive_all_pids:
            self.managed_pids.add(pid)
            is_audio = pid in audio_active_descendants
            try:
                if is_audio:
                    # Protegido para audio sin micro-cortes
                    os.sched_setscheduler(pid, os.SCHED_OTHER, os.sched_param(0))
                    os.setpriority(os.PRIO_PROCESS, pid, 8)
                    set_process_ioprio(pid, IOPRIO_CLASS_BE, 4)
                    protected_count += 1
                else:
                    # Aislamiento completo de reposo
                    os.sched_setscheduler(pid, os.SCHED_IDLE, os.sched_param(0))
                    os.setpriority(os.PRIO_PROCESS, pid, 19)
                    set_process_ioprio(pid, IOPRIO_CLASS_IDLE, 0)
                    throttled_count += 1
            except (ProcessLookupError, PermissionError):
                pass

        self.log(f"Workspace {active_ws} activo | Promovidos: {len(active_all_pids)} | Reducidos (SCHED_IDLE): {throttled_count} | Protegidos (audio): {protected_count}")

    def restore_all(self) -> None:
        self.log("Restaurando todos los procesos a prioridad normal...")
        for pid in list(self.managed_pids):
            try:
                os.sched_setscheduler(pid, os.SCHED_OTHER, os.sched_param(0))
                os.setpriority(os.PRIO_PROCESS, pid, 0)
                set_process_ioprio(pid, IOPRIO_CLASS_BE, 0)
            except (ProcessLookupError, PermissionError):
                pass
        self.managed_pids.clear()

    def run(self) -> None:
        sock_path = self.find_socket()
        self.log(f"Conectado a socket IPC Hyprland: {sock_path}")
        
        # Aplicacion inicial
        self.apply_governor()

        while self.running:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(sock_path)
                s.settimeout(None) # Bloqueante: 0% CPU mientras no haya eventos

                buffer = ""
                while self.running:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    buffer += chunk.decode("utf-8", errors="ignore")
                    lines = buffer.split("\n")
                    buffer = lines.pop()

                    needs_update = False
                    for line in lines:
                        if not line:
                            continue
                        event_name = line.split(">>")[0]
                        # Eventos que cambian el espacio de trabajo o distribucion de ventanas
                        if event_name in ("workspace", "workspacev2", "focusedmon", "openwindow", "closewindow", "movewindow", "destroyworkspace"):
                            needs_update = True
                            break

                    if needs_update:
                        self.apply_governor()

                s.close()
            except Exception as e:
                if not self.running:
                    break
                self.log(f"Error o reconexion de socket: {e}. Reintentando en 2 segundos...")
                time.sleep(2)
                try:
                    sock_path = self.find_socket()
                except Exception:
                    pass

def main():
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    governor = HyprWorkspaceGovernor(verbose=verbose)

    def handle_signal(sig, frame):
        governor.running = False
        governor.restore_all()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    governor.run()

if __name__ == "__main__":
    main()

