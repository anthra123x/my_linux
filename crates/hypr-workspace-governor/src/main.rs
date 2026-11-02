//! hypr-workspace-governor (Rust)
//!
//! Gobernador de recursos de espacios de trabajo para Hyprland de alto rendimiento.
//! Aísla el consumo de CPU, I/O y memoria hacia el espacio de trabajo en foco.
//!
//! Características:
//! - Cero sobrecarga de subprocesos: comunicación nativa por sockets IPC de Hyprland (.socket.sock y .socket2.sock).
//! - Árbol de procesos en RAM mediante lectura directa de /proc (sin invocar subshells ni pgrep).
//! - Llamadas directas al kernel de Linux mediante libc (sched_setscheduler, setpriority, SYS_ioprio_set).
//! - Protección de audio: no penaliza reproductores ni aplicaciones con sonido activo (PipeWire/PulseAudio).
//! - Restauración determinista de prioridades al salir (SIGINT / SIGTERM).

use libc::{c_int, c_long, id_t, PRIO_PROCESS, SCHED_IDLE, SCHED_OTHER};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const SYS_IOPRIO_SET: c_long = 251;
const IOPRIO_WHO_PROCESS: c_int = 1;
const IOPRIO_CLASS_BE: c_int = 2;
const IOPRIO_CLASS_IDLE: c_int = 3;

static RUNNING: AtomicBool = AtomicBool::new(true);
static MANAGED_PIDS: Mutex<Option<HashSet<i32>>> = Mutex::new(None);

#[derive(Debug, Deserialize)]
struct ActiveWorkspace {
    id: i32,
}

#[derive(Debug, Deserialize)]
struct WorkspaceRef {
    id: i32,
}

#[derive(Debug, Deserialize)]
struct Client {
    pid: i32,
    workspace: WorkspaceRef,
    #[serde(default)]
    #[allow(dead_code)]
    class: String,
}

#[derive(Debug, Deserialize)]
struct SinkInput {
    properties: Option<SinkProperties>,
}

#[derive(Debug, Deserialize)]
struct SinkProperties {
    #[serde(rename = "application.process.id")]
    process_id: Option<String>,
}

unsafe fn set_ioprio(pid: i32, ioclass: c_int, iodata: c_int) {
    let prio = (ioclass << 13) | (iodata & 0x1FFF);
    libc::syscall(SYS_IOPRIO_SET, IOPRIO_WHO_PROCESS, pid, prio);
}

unsafe fn set_policy(pid: i32, policy: c_int) {
    let param = libc::sched_param { sched_priority: 0 };
    libc::sched_setscheduler(pid, policy, &param);
}

unsafe fn set_nice(pid: i32, nice: c_int) {
    libc::setpriority(PRIO_PROCESS, pid as id_t, nice);
}

fn restore_all_pids() {
    if let Ok(mut guard) = MANAGED_PIDS.lock() {
        if let Some(ref pids) = *guard {
            for &pid in pids {
                unsafe {
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 0);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 0);
                }
            }
        }
        *guard = None;
    }
}

extern "C" fn sig_handler(_: c_int) {
    RUNNING.store(false, Ordering::SeqCst);
}

fn find_hypr_socket_dir() -> Option<PathBuf> {
    let xdg = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::getuid() }));
    let base = Path::new(&xdg).join("hypr");
    if let Ok(entries) = fs::read_dir(&base) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() && p.join(".socket2.sock").exists() {
                return Some(p);
            }
        }
    }
    if let Ok(his) = std::env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        let p = base.join(his);
        if p.join(".socket2.sock").exists() {
            return Some(p);
        }
    }
    None
}

fn query_hypr_command(dir: &Path, cmd: &str) -> Option<String> {
    let sock_path = dir.join(".socket.sock");
    let mut stream = UnixStream::connect(sock_path).ok()?;
    stream.set_read_timeout(Some(Duration::from_millis(500))).ok()?;
    stream.set_write_timeout(Some(Duration::from_millis(500))).ok()?;
    stream.write_all(cmd.as_bytes()).ok()?;
    
    let mut buf = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(_) => break,
        }
    }
    String::from_utf8(buf).ok()
}

fn get_audio_pids() -> HashSet<i32> {
    let mut pids = HashSet::new();
    if let Ok(output) = Command::new("pactl")
        .args(["-f", "json", "list", "sink-inputs"])
        .output()
    {
        if output.status.success() {
            if let Ok(sinks) = serde_json::from_slice::<Vec<SinkInput>>(&output.stdout) {
                for s in sinks {
                    if let Some(props) = s.properties {
                        if let Some(id_str) = props.process_id {
                            if let Ok(pid) = id_str.parse::<i32>() {
                                pids.insert(pid);
                            }
                        }
                    }
                }
            }
        }
    }
    pids
}

fn build_process_tree() -> HashMap<i32, Vec<i32>> {
    let mut tree: HashMap<i32, Vec<i32>> = HashMap::new();
    let proc_dir = Path::new("/proc");
    if let Ok(entries) = fs::read_dir(proc_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if let Ok(pid) = name_str.parse::<i32>() {
                let stat_file = entry.path().join("stat");
                if let Ok(contents) = fs::read_to_string(stat_file) {
                    if let Some(rparen) = contents.rfind(')') {
                        let rest = &contents[rparen + 2..];
                        let parts: Vec<&str> = rest.split_whitespace().collect();
                        if parts.len() >= 2 {
                            if let Ok(ppid) = parts[1].parse::<i32>() {
                                tree.entry(ppid).or_default().push(pid);
                            }
                        }
                    }
                }
            }
        }
    }
    tree
}

fn expand_pids_and_threads(roots: &HashSet<i32>, tree: &HashMap<i32, Vec<i32>>) -> HashSet<i32> {
    let mut all = HashSet::new();
    let mut stack: Vec<i32> = roots.iter().copied().collect();

    while let Some(curr) = stack.pop() {
        if all.insert(curr) {
            // Hijos
            if let Some(children) = tree.get(&curr) {
                for &c in children {
                    if !all.contains(&c) {
                        stack.push(c);
                    }
                }
            }
            // Hilos en /proc/<pid>/task/
            let task_dir = Path::new("/proc").join(curr.to_string()).join("task");
            if let Ok(entries) = fs::read_dir(task_dir) {
                for entry in entries.flatten() {
                    if let Ok(tid) = entry.file_name().to_string_lossy().parse::<i32>() {
                        all.insert(tid);
                    }
                }
            }
        }
    }
    all
}

fn apply_governor(dir: &Path, verbose: bool) {
    let start = Instant::now();
    let ws_json = match query_hypr_command(dir, "j/activeworkspace") {
        Some(s) => s,
        None => return,
    };
    let active_ws: ActiveWorkspace = match serde_json::from_str(&ws_json) {
        Ok(w) => w,
        Err(_) => return,
    };

    let cl_json = match query_hypr_command(dir, "j/clients") {
        Some(s) => s,
        None => return,
    };
    let clients: Vec<Client> = match serde_json::from_str(&cl_json) {
        Ok(c) => c,
        Err(_) => return,
    };

    let audio_roots = get_audio_pids();
    let proc_tree = build_process_tree();

    let mut active_roots = HashSet::new();
    let mut inactive_roots = HashSet::new();

    for c in &clients {
        if c.pid <= 1 {
            continue;
        }
        if c.workspace.id == active_ws.id {
            active_roots.insert(c.pid);
        } else {
            inactive_roots.insert(c.pid);
        }
    }

    // Si una aplicación tiene ventanas en ambos espacios, gana el activo
    for p in &active_roots {
        inactive_roots.remove(p);
    }

    let active_all = expand_pids_and_threads(&active_roots, &proc_tree);
    let mut inactive_all = expand_pids_and_threads(&inactive_roots, &proc_tree);

    for p in &active_all {
        inactive_all.remove(p);
    }

    let audio_all = expand_pids_and_threads(&audio_roots, &proc_tree);

    // Guardar lista gestionada para restauración limpia
    let mut current_managed = HashSet::new();

    // 1. Promover procesos activos a SCHED_OTHER, nice 0, E/S normal
    for &pid in &active_all {
        current_managed.insert(pid);
        unsafe {
            set_policy(pid, SCHED_OTHER);
            set_nice(pid, 0);
            set_ioprio(pid, IOPRIO_CLASS_BE, 0);
        }
    }

    let mut throttled = 0;
    let mut protected = 0;

    // 2. Reducir procesos inactivos
    for &pid in &inactive_all {
        current_managed.insert(pid);
        let has_audio = audio_all.contains(&pid);
        unsafe {
            if has_audio {
                // Protegido para audio sin micro-cortes
                set_policy(pid, SCHED_OTHER);
                set_nice(pid, 8);
                set_ioprio(pid, IOPRIO_CLASS_BE, 4);
                protected += 1;
            } else {
                // Aislamiento completo de reposo
                set_policy(pid, SCHED_IDLE);
                set_nice(pid, 19);
                set_ioprio(pid, IOPRIO_CLASS_IDLE, 0);
                throttled += 1;
            }
        }
    }

    if let Ok(mut guard) = MANAGED_PIDS.lock() {
        *guard = Some(current_managed);
    }

    if verbose {
        let elapsed = start.elapsed();
        println!(
            "[governor-rs] Workspace {} activo | Promovidos: {} | SCHED_IDLE: {} | Audio protegido: {} ({:?})",
            active_ws.id,
            active_all.len(),
            throttled,
            protected,
            elapsed
        );
    }
}

fn main() {
    let verbose = std::env::args().any(|a| a == "--verbose" || a == "-v");

    unsafe {
        libc::signal(libc::SIGINT, sig_handler as *const () as usize);
        libc::signal(libc::SIGTERM, sig_handler as *const () as usize);
    }

    let dir = match find_hypr_socket_dir() {
        Some(d) => d,
        None => {
            eprintln!("[governor-rs] Error: No se encontro el socket IPC de Hyprland.");
            std::process::exit(1);
        }
    };

    if verbose {
        println!("[governor-rs] Conectado a socket Hyprland en: {:?}", dir);
    }

    // Aplicar estado inicial
    apply_governor(&dir, verbose);

    while RUNNING.load(Ordering::SeqCst) {
        let s2_path = dir.join(".socket2.sock");
        let stream = match UnixStream::connect(&s2_path) {
            Ok(s) => s,
            Err(_) => {
                std::thread::sleep(Duration::from_secs(1));
                continue;
            }
        };

        // Timeout de lectura para chequear señal de parada de forma cooperativa
        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
        let mut reader = BufReader::new(stream);
        let mut line = String::new();

        while RUNNING.load(Ordering::SeqCst) {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break, // Socket cerrado, reconectar
                Ok(_) => {
                    let event = line.split(">>").next().unwrap_or("").trim();
                    match event {
                        "workspace" | "workspacev2" | "focusedmon" | "openwindow"
                        | "closewindow" | "movewindow" | "destroyworkspace" => {
                            apply_governor(&dir, verbose);
                        }
                        _ => {}
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock || e.kind() == std::io::ErrorKind::TimedOut => {
                    // Timeout esperado, permite evaluar RUNNING
                    continue;
                }
                Err(_) => break, // Error de socket, reconectar
            }
        }
    }

    if verbose {
        println!("[governor-rs] Deteniendo gobernador y restaurando prioridades...");
    }
    restore_all_pids();
}
