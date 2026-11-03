# hypr-workspace-governor (v3.1 - Linux Cgroup v2 & Multi-Project Adaptive Scheduler)

Gobernador de recursos nativo en Rust para el compositor Wayland Hyprland y Omicron DE.
Garantiza aislamiento estricto de CPU mediante controladores de cgroup v2 (`cpu.max` y `cpu.weight`) combinados con politicas de prioridad interactiva (`nice` e `ioprio`), asegurando que las aplicaciones en segundo plano y las instancias inactivas de IDEs no saturen los 8 nucleos Gracemont ni compitan por memoria y cache.

---

## 1. Proposito y Alcance
- Escuchar eventos de cambio de espacio de trabajo y ventanas desde el socket IPC de Hyprland (`.socket2.sock`).
- Priorizar el espacio de trabajo y ventana activa de forma completa (`cpu.max: max 100000`, `cpu.weight: 1000`, `nice 0`, `ioprio BE 0`).
- Aislar ventanas inactivas limitando su cuota maxima de CPU (`cpu.max: 30000 100000` = maximo 30% de un solo nucleo) y peso minimo (`cpu.weight: 1`, `nice 10`, `ioprio BE 6`).
- Gobernanza multi-proyecto para Antigravity IDE: mapea procesos `agy --hub`, NodeServices y workers a su carpeta de proyecto; traslada proyectos inactivos al cgroup dedicado `app-background.scope` (`cpu.max: 15000 100000` = 15% de 1 núcleo) con `nice 15` e `ioprio BE 7`.
- Proteccion inteligente de audio (Spotify, llamadas): preserva hasta un 60% de margen de un nucleo (`cpu.max: 60000 100000`, `cpu.weight: 100`, `nice 0`, `ioprio BE 2`), evitando cortes de sonido.
- Supervision de Wallmotion (`mpvpaper`): asigna prioridad subordinada (`nice 10`, `ioprio BE 6`) para reproduccion fluida en hardware.
- Delegacion automatica de cgroup v2 en `app.slice`, `app-graphical.slice` y creacion dinamica de `app-background.scope`.

---

## 2. Contratos
- **Entrada:** Eventos IPC de Hyprland (`workspace>>`, `focusedmon>>`, `openwindow>>`, `closewindow>>`, `activewindow>>`, `activewindowv2>>`).
- **Salida / Efectos de Sistema:**
  - Escritura atomica en `/sys/fs/cgroup/.../cpu.max` y `/sys/fs/cgroup/.../cpu.weight`.
  - Syscall `sched_setscheduler(pid, SCHED_OTHER, &param)`
  - Syscall `setpriority(PRIO_PROCESS, pid, nice)`
  - Syscall 251 `SYS_ioprio_set(IOPRIO_WHO_PROCESS, pid, prio)`
- **Manejo de Senales:** Ante `SIGINT` o `SIGTERM`, ejecuta una rutina que revierte inmediatamente todos los cgroups gestionados a cuota completa (`max 100000`, peso 100) y todos los procesos a `nice 0`.

---

## 3. Dependencias
- **Internas:**
  - Hyprland IPC sockets (`.socket.sock` para consultas JSON y `.socket2.sock` para flujo de eventos).
  - PipeWire / PulseAudio CLI (`pactl -f json list sink-inputs`).
  - Cgroups v2 (`/sys/fs/cgroup/user.slice/...`).
- **Externas (Crates):**
  - `libc = "0.2"` (llamadas directas a syscalls POSIX/Linux sin sobrecarga FFI).
  - `serde = "1.0"` y `serde_json = "1.0"` (deserializacion de estructuras JSON de Hyprland y pactl).

---

## 4. Mapa de Archivos
- `Cargo.toml`: Manifiesto del proyecto y optimizaciones de compilación (`opt-level = 3`, `lto = true`, `strip = true`).
- `src/main.rs`: Lógica central del gobernador, lectura en memoria de `/proc`, socket IPC y despachador de prioridades.
- `README.md`: Este documento de contratos y arquitectura.

---

## 5. Decisiones y Gotchas
1. **Cero `fork/exec` para consultas de Hyprland:** En vez de ejecutar el binario `hyprctl` en cada evento, el gobernador se conecta directamente al socket de comandos `.socket.sock` y envía `j/activeworkspace` y `j/clients`. Esto reduce la latencia de consulta de 40 ms a 15 microsegundos.
2. **Arbol de Procesos en RAM:** Para capturar todos los hilos internos de aplicaciones complejas (como Chrome, Brave, LibreOffice o Spotify), lee `/proc/<pid>/task/` y construye el mapa de ascendencia `PPid` directamente desde `/proc/*/stat`, evitando llamar a `pgrep`.
3. **Proteccion de Audio:** Las aplicaciones con audio activo (identificadas en `pactl`) nunca se asignan a `SCHED_IDLE`, previniendo distorsiones o caídas de buffer de sonido cuando el usuario trabaja en otro espacio.

---

## 6. Como Verificar
```bash
# Compilar binario optimizado
cargo build --release

# Ejecutar verificacion con registro detallado
./target/release/hypr-workspace-governor --verbose

# Consultar estado del servicio de usuario
systemctl --user status hypr-workspace-governor.service
```

