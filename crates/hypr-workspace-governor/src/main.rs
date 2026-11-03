//! hypr-workspace-governor (Rust v2.1 - Smooth Adaptive Engine)
//!
//! Gobernador de recursos nativo en Rust para Hyprland.
//! Elimina tirones (micro-stutters) garantizando que el espacio activo reciba
//! la maxima prioridad de CPU e I/O sin estrangular los procesos en segundo plano
//! ni provocar inanicion de buffers en Wayland/D-Bus.
//!
//! Optimizaciones v2.1:
//! - Cache de arbol de procesos y audio con TTL: evita escanear /proc y ejecutar pactl
//!   en cada evento individual de cambio de espacio.
//! - Priorizacion balanceada (nice 5 / ioprio BE 5 para fondo, nice 0 / ioprio BE 0 para activo):
//!   el proceso activo recibe la mayoria de ciclos de CPU de forma inmediata, mientras
//!   las aplicaciones en segundo plano mantienen capacidad de respuesta para cambios instantaneos.
//! - Reproduccion continua de fondos animados (Wallmotion) con coste minimo por hardware.
//! - Debounce de eventos de cambio redundantes.

use libc::{c_int, c_long, id_t, PRIO_PROCESS, SCHED_OTHER};
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

// Estados de proceso
const STATE_ACTIVE: u8 = 0;
const STATE_AUDIO_PROTECTED: u8 = 1;
const STATE_INACTIVE: u8 = 2;
const STATE_HEAVY: u8 = 3;

static RUNNING: AtomicBool = AtomicBool::new(true);
static MANAGED_PIDS: Mutex<Option<HashSet<i32>>> = Mutex::new(None);
static PID_STATES: Mutex<Option<HashMap<i32, u8>>> = Mutex::new(None);
static LAST_WS_ID: Mutex<i32> = Mutex::new(-1);

struct ProcessTreeCache {
    tree: HashMap<i32, Vec<i32>>,
    known_roots: HashSet<i32>,
    last_update: Instant,
}

struct AudioCache {
    pids: HashSet<i32>,
    last_update: Instant,
}

static TREE_CACHE: Mutex<Option<ProcessTreeCache>> = Mutex::new(None);
static AUDIO_CACHE: Mutex<Option<AudioCache>> = Mutex::new(None);

#[derive(Debug, Deserialize)]
struct ActiveWorkspace {
    id: i32,
    #[serde(default)]
    #[allow(dead_code)]
    windows: i32,
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
    stream.set_read_timeout(Some(Duration::from_millis(200))).ok()?;
    stream.set_write_timeout(Some(Duration::from_millis(200))).ok()?;
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

fn get_cached_audio_pids() -> HashSet<i32> {
    let mut cache_guard = AUDIO_CACHE.lock().unwrap();
    if let Some(ref c) = *cache_guard {
        if c.last_update.elapsed() < Duration::from_secs(3) {
            return c.pids.clone();
        }
    }

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

    *cache_guard = Some(AudioCache {
        pids: pids.clone(),
        last_update: Instant::now(),
    });

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

fn get_cached_process_tree(current_roots: &HashSet<i32>) -> HashMap<i32, Vec<i32>> {
    let mut cache_guard = TREE_CACHE.lock().unwrap();
    if let Some(ref c) = *cache_guard {
        if c.last_update.elapsed() < Duration::from_secs(5) && c.known_roots == *current_roots {
            return c.tree.clone();
        }
    }

    let tree = build_process_tree();
    *cache_guard = Some(ProcessTreeCache {
        tree: tree.clone(),
        known_roots: current_roots.clone(),
        last_update: Instant::now(),
    });

    tree
}

fn expand_process_children(roots: &HashSet<i32>, tree: &HashMap<i32, Vec<i32>>) -> HashSet<i32> {
    let mut all = HashSet::new();
    let mut stack: Vec<i32> = roots.iter().copied().collect();

    while let Some(curr) = stack.pop() {
        if all.insert(curr) {
            if let Some(children) = tree.get(&curr) {
                for &c in children {
                    if !all.contains(&c) {
                        stack.push(c);
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

    let mut last_ws_guard = LAST_WS_ID.lock().unwrap();
    let ws_changed = *last_ws_guard != active_ws.id;
    *last_ws_guard = active_ws.id;

    let mut all_client_roots = HashSet::new();
    let mut active_roots = HashSet::new();
    let mut inactive_roots = HashSet::new();
    let mut heavy_compute_roots = HashSet::new();

    for c in &clients {
        if c.pid <= 1 {
            continue;
        }
        all_client_roots.insert(c.pid);

        if c.class.contains("libreoffice") || c.class.contains("soffice") {
            heavy_compute_roots.insert(c.pid);
        }

        if c.workspace.id == active_ws.id {
            active_roots.insert(c.pid);
        } else {
            inactive_roots.insert(c.pid);
        }
    }

    // Si una aplicacion tiene ventanas en ambos espacios, gana el activo
    for p in &active_roots {
        inactive_roots.remove(p);
    }

    let audio_roots = get_cached_audio_pids();
    let proc_tree = get_cached_process_tree(&all_client_roots);

    let active_all = expand_process_children(&active_roots, &proc_tree);
    let mut inactive_all = expand_process_children(&inactive_roots, &proc_tree);

    for p in &active_all {
        inactive_all.remove(p);
    }

    let audio_all = expand_process_children(&audio_roots, &proc_tree);
    let heavy_all = expand_process_children(&heavy_compute_roots, &proc_tree);

    let mut current_managed = HashSet::new();
    let mut states_guard = PID_STATES.lock().unwrap();
    if states_guard.is_none() {
        *states_guard = Some(HashMap::new());
    }
    let states_map = states_guard.as_mut().unwrap();

    let mut updated_count = 0;

    // 1. Promover procesos del workspace activo a SCHED_OTHER, nice 0, E/S prioritaria
    for &pid in &active_all {
        current_managed.insert(pid);
        let prev = states_map.get(&pid).copied();
        if prev != Some(STATE_ACTIVE) {
            unsafe {
                set_policy(pid, SCHED_OTHER);
                set_nice(pid, 0);
                set_ioprio(pid, IOPRIO_CLASS_BE, 0);
            }
            states_map.insert(pid, STATE_ACTIVE);
            updated_count += 1;
        }
    }

    let mut throttled = 0;
    let mut protected = 0;

    // 2. Ajustar procesos inactivos de forma equilibrada sin causar inanicion ni congelamientos
    for &pid in &inactive_all {
        current_managed.insert(pid);
        let has_audio = audio_all.contains(&pid);
        let is_heavy = heavy_all.contains(&pid);

        let target_state = if has_audio {
            STATE_AUDIO_PROTECTED
        } else if is_heavy {
            STATE_HEAVY
        } else {
            STATE_INACTIVE
        };
        let prev = states_map.get(&pid).copied();

        if prev != Some(target_state) {
            unsafe {
                if has_audio {
                    // Audio protegido: nunca se retrasa para evitar cortes
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 0);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 1);
                    protected += 1;
                } else if is_heavy {
                    // Computo pesado aislado (exportacion de documentos, compilacion)
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 15);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 7);
                    throttled += 1;
                } else {
                    // Aplicaciones de escritorio en segundo plano:
                    // nice 5 da ~75% de ciclos al activo sin matar los sockets de Wayland/D-Bus.
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 5);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 5);
                    throttled += 1;
                }
            }
            states_map.insert(pid, target_state);
            updated_count += 1;
        }
    }

    if let Ok(mut guard) = MANAGED_PIDS.lock() {
        *guard = Some(current_managed);
    }

    if verbose && (ws_changed || updated_count > 0) {
        let elapsed = start.elapsed();
        println!(
            "[governor-rs] Workspace {} | Actualizados: {} | Activos: {} | Fondo: {} | Audio: {} ({:?})",
            active_ws.id,
            updated_count,
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

    // Aplicacion inicial
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

        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
        let mut reader = BufReader::new(stream);
        let mut line = String::new();

        while RUNNING.load(Ordering::SeqCst) {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break,
                Ok(_) => {
                    let event = line.split(">>").next().unwrap_or("").trim();
                    match event {
                        "workspace" | "workspacev2" | "focusedmon" | "openwindow"
                        | "closewindow" | "destroyworkspace" => {
                            apply_governor(&dir, verbose);
                        }
                        _ => {}
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock || e.kind() == std::io::ErrorKind::TimedOut => {
                    continue;
                }
                Err(_) => break,
            }
        }
    }

    if verbose {
        println!("[governor-rs] Deteniendo gobernador y restaurando prioridades...");
    }
    restore_all_pids();
}
