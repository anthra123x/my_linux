//! hypr-workspace-governor (Rust v3.1 - Linux Cgroup v2 & Multi-Project Adaptive Scheduler)
//!
//! Gobernador de recursos nativo en Rust para Hyprland (Omicron DE).
//! Implementa Aislamiento Activo de Recursos mediante controladores de cgroup v2
//! del kernel Linux (cpu.max y cpu.weight) combinados con politicas de prioridad
//! interactiva (nice e ioprio).
//!
//! Novedades v3.1:
//! - Gobernanza Multi-Proyecto para Antigravity IDE:
//!   Mapea los arboles de extensiones (NodeService), hubs de agentes (agy) y workers
//!   a su directorio de trabajo (--add-dir) y ventana de Hyprland.
//! - Aislamiento en cgroup v2 dedicado (app-background.scope):
//!   Limita fisicamente al 15% de 1 nucleo (cpu.max = 15000 100000) los hubs y
//!   renderers de proyectos en segundo plano, impidiendo que saturen los 8 nucleos
//!   Gracemont o interfieran entre sesiones activas.
//! - Reactivacion atomica en < 10 ms al cambiar de ventana o espacio de trabajo.
//! - Proteccion de audio PipeWire y fondos animados con aceleracion por hardware.

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
static MANAGED_CGROUPS: Mutex<Option<HashSet<PathBuf>>> = Mutex::new(None);
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
    #[serde(default)]
    title: String,
}

#[derive(Debug, Deserialize)]
struct ActiveWindow {
    #[serde(default)]
    class: String,
    #[serde(default)]
    title: String,
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

#[derive(Debug, Deserialize)]
struct WallmotionPidFile {
    #[serde(default)]
    pids: Vec<i32>,
}

struct HubProcess {
    pid: i32,
    ppid: i32,
    project_folder: String,
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

fn get_user_background_cgroup() -> PathBuf {
    let uid = unsafe { libc::getuid() };
    PathBuf::from(format!(
        "/sys/fs/cgroup/user.slice/user-{}.slice/user@{}.service/app-background.scope",
        uid, uid
    ))
}

fn get_user_app_cgroup() -> PathBuf {
    let uid = unsafe { libc::getuid() };
    PathBuf::from(format!(
        "/sys/fs/cgroup/user.slice/user-{}.slice/user@{}.service/app.slice",
        uid, uid
    ))
}

fn ensure_cgroup_cpu_controller() {
    let uid = unsafe { libc::getuid() };
    let targets = [
        format!(
            "/sys/fs/cgroup/user.slice/user-{}.slice/user@{}.service/cgroup.subtree_control",
            uid, uid
        ),
        format!(
            "/sys/fs/cgroup/user.slice/user-{}.slice/user@{}.service/app.slice/cgroup.subtree_control",
            uid, uid
        ),
        format!(
            "/sys/fs/cgroup/user.slice/user-{}.slice/user@{}.service/app.slice/app-graphical.slice/cgroup.subtree_control",
            uid, uid
        ),
    ];

    for t in &targets {
        let p = Path::new(t);
        if p.exists() {
            if let Ok(mut f) = fs::OpenOptions::new().write(true).open(p) {
                let _ = f.write_all(b"+cpu\n");
            }
        }
    }
}

fn get_cgroup_dir_for_pid(pid: i32) -> Option<PathBuf> {
    let cg_file = format!("/proc/{}/cgroup", pid);
    let contents = fs::read_to_string(cg_file).ok()?;
    for line in contents.lines() {
        if let Some(rest) = line.strip_prefix("0::") {
            let trimmed = rest.trim_start_matches('/');
            if !trimmed.is_empty() {
                let p = Path::new("/sys/fs/cgroup").join(trimmed);
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }
    None
}

fn set_cgroup_limits(cg: &Path, cpu_max: &str, cpu_weight: &str) {
    let max_file = cg.join("cpu.max");
    if max_file.exists() {
        let _ = fs::write(max_file, cpu_max);
    }
    let weight_file = cg.join("cpu.weight");
    if weight_file.exists() {
        let _ = fs::write(weight_file, cpu_weight);
    }
}

fn extract_project_name(title: &str) -> Option<String> {
    if let Some(pos) = title.find(" - Antigravity IDE") {
        let name = title[..pos].trim();
        if !name.is_empty() {
            return Some(name.to_string());
        }
    }
    None
}

fn scan_antigravity_hubs() -> Vec<HubProcess> {
    let mut hubs = Vec::new();
    let proc_dir = Path::new("/proc");
    let entries = match fs::read_dir(proc_dir) {
        Ok(e) => e,
        Err(_) => return hubs,
    };

    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if let Ok(pid) = name_str.parse::<i32>() {
            let cmd_file = entry.path().join("cmdline");
            if let Ok(bytes) = fs::read(&cmd_file) {
                let cmd = String::from_utf8_lossy(&bytes);
                if cmd.contains("agy") && cmd.contains("--add-dir=") {
                    let mut folder_opt = None;
                    for arg in cmd.split('\0') {
                        if let Some(dir) = arg.strip_prefix("--add-dir=") {
                            let p = Path::new(dir.trim_end_matches('/'));
                            if let Some(fname) = p.file_name() {
                                folder_opt = Some(fname.to_string_lossy().to_string());
                                break;
                            }
                        }
                    }
                    if let Some(folder) = folder_opt {
                        let stat_file = entry.path().join("stat");
                        let ppid = if let Ok(contents) = fs::read_to_string(stat_file) {
                            if let Some(rparen) = contents.rfind(')') {
                                let rest = &contents[rparen + 2..];
                                let parts: Vec<&str> = rest.split_whitespace().collect();
                                parts
                                    .get(1)
                                    .and_then(|s| s.parse::<i32>().ok())
                                    .unwrap_or(0)
                            } else {
                                0
                            }
                        } else {
                            0
                        };
                        hubs.push(HubProcess {
                            pid,
                            ppid,
                            project_folder: folder,
                        });
                    }
                }
            }
        }
    }
    hubs
}

fn restore_all_pids() {
    if let Ok(mut guard) = MANAGED_PIDS.lock() {
        if let Some(ref pids) = *guard {
            let app_cg = get_user_app_cgroup();
            let app_procs = app_cg.join("cgroup.procs");
            for &pid in pids {
                if pid > 1 {
                    let _ = fs::write(&app_procs, format!("{}\n", pid));
                    unsafe {
                        set_policy(pid, SCHED_OTHER);
                        set_nice(pid, 0);
                        set_ioprio(pid, IOPRIO_CLASS_BE, 0);
                    }
                }
            }
        }
        *guard = None;
    }

    if let Ok(mut guard) = MANAGED_CGROUPS.lock() {
        if let Some(ref cgroups) = *guard {
            for cg in cgroups {
                set_cgroup_limits(cg, "max 100000\n", "100\n");
            }
        }
        *guard = None;
    }

    let bg_cg = get_user_background_cgroup();
    if bg_cg.exists() {
        set_cgroup_limits(&bg_cg, "max 100000\n", "100\n");
    }
}

extern "C" fn sig_handler(_: c_int) {
    RUNNING.store(false, Ordering::SeqCst);
}

fn find_hypr_socket_dir() -> Option<PathBuf> {
    let xdg = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::getuid() }));
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
    stream
        .set_read_timeout(Some(Duration::from_millis(200)))
        .ok()?;
    stream
        .set_write_timeout(Some(Duration::from_millis(200)))
        .ok()?;
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

fn govern_wallmotion() {
    let uid = unsafe { libc::getuid() };
    let pidfile = PathBuf::from(format!("/run/user/{}/wallmotion/pids.json", uid));
    if let Ok(contents) = fs::read_to_string(pidfile) {
        if let Ok(data) = serde_json::from_str::<WallmotionPidFile>(&contents) {
            for pid in data.pids {
                if pid > 1 {
                    unsafe {
                        set_nice(pid, 10);
                        set_ioprio(pid, IOPRIO_CLASS_BE, 6);
                    }
                }
            }
        }
    }
}

fn apply_governor(dir: &Path, verbose: bool) {
    let start = Instant::now();
    ensure_cgroup_cpu_controller();

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

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Mapeo de Proyectos de Antigravity IDE (Multi-Workspace Isolation)
    // ─────────────────────────────────────────────────────────────────────────
    let mut active_projects = HashSet::new();
    let mut inactive_projects = HashSet::new();

    if let Some(act_win_json) = query_hypr_command(dir, "j/activewindow") {
        if let Ok(act_win) = serde_json::from_str::<ActiveWindow>(&act_win_json) {
            if act_win.class.contains("antigravity") {
                if let Some(proj) = extract_project_name(&act_win.title) {
                    active_projects.insert(proj);
                }
            }
        }
    }

    for c in &clients {
        if c.class.contains("antigravity") {
            if let Some(proj) = extract_project_name(&c.title) {
                if c.workspace.id == active_ws.id {
                    active_projects.insert(proj);
                } else {
                    inactive_projects.insert(proj);
                }
            }
        }
    }

    for p in &active_projects {
        inactive_projects.remove(p);
    }

    let mut all_client_roots = HashSet::new();
    let mut active_roots = HashSet::new();
    let mut inactive_roots = HashSet::new();
    let mut heavy_compute_roots = HashSet::new();

    let mut active_cgroups = HashSet::new();
    let mut inactive_cgroups = HashSet::new();
    let mut heavy_cgroups = HashSet::new();

    for c in &clients {
        if c.pid <= 1 {
            continue;
        }
        all_client_roots.insert(c.pid);
        let cg_opt = get_cgroup_dir_for_pid(c.pid);

        if c.class.contains("libreoffice") || c.class.contains("soffice") {
            heavy_compute_roots.insert(c.pid);
            if let Some(ref cg) = cg_opt {
                heavy_cgroups.insert(cg.clone());
            }
        }

        if c.workspace.id == active_ws.id {
            active_roots.insert(c.pid);
            if let Some(ref cg) = cg_opt {
                active_cgroups.insert(cg.clone());
            }
        } else {
            inactive_roots.insert(c.pid);
            if let Some(ref cg) = cg_opt {
                inactive_cgroups.insert(cg.clone());
            }
        }
    }

    for cg in &active_cgroups {
        inactive_cgroups.remove(cg);
    }
    for p in &active_roots {
        inactive_roots.remove(p);
    }

    let audio_roots = get_cached_audio_pids();
    let mut audio_cgroups = HashSet::new();
    for &apid in &audio_roots {
        if let Some(cg) = get_cgroup_dir_for_pid(apid) {
            audio_cgroups.insert(cg);
        }
    }

    let proc_tree = get_cached_process_tree(&all_client_roots);
    let mut active_all = expand_process_children(&active_roots, &proc_tree);
    let mut inactive_all = expand_process_children(&inactive_roots, &proc_tree);

    for p in &active_all {
        inactive_all.remove(p);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Localización y Gobernanza de Hubs de Agentes y Extensiones
    // ─────────────────────────────────────────────────────────────────────────
    let hubs = scan_antigravity_hubs();
    let mut proj_active_roots = HashSet::new();
    let mut proj_inactive_roots = HashSet::new();

    for hub in hubs {
        let is_active = active_projects.iter().any(|p| {
            p == &hub.project_folder
                || hub.project_folder.contains(p)
                || p.contains(&hub.project_folder)
        });

        if is_active {
            proj_active_roots.insert(hub.pid);
            if hub.ppid > 1 {
                proj_active_roots.insert(hub.ppid);
            }
        } else {
            proj_inactive_roots.insert(hub.pid);
            if hub.ppid > 1 {
                proj_inactive_roots.insert(hub.ppid);
            }
        }
    }

    for p in &proj_active_roots {
        proj_inactive_roots.remove(p);
    }

    let proj_active_all = expand_process_children(&proj_active_roots, &proc_tree);
    let mut proj_inactive_all = expand_process_children(&proj_inactive_roots, &proc_tree);
    for p in &proj_active_all {
        proj_inactive_all.remove(p);
    }

    // Transferir PIDs de proyectos inactivos fuera de active_all
    for p in &proj_inactive_all {
        active_all.remove(p);
        inactive_all.insert(*p);
    }
    for p in &proj_active_all {
        inactive_all.remove(p);
        active_all.insert(*p);
    }

    let audio_all = expand_process_children(&audio_roots, &proc_tree);
    let heavy_all = expand_process_children(&heavy_compute_roots, &proc_tree);

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Control de Cgroups v2 (Nivel Kernel)
    // ─────────────────────────────────────────────────────────────────────────
    let mut current_cgroups = HashSet::new();

    // Cgroups de aplicaciones en primer plano (max 100000)
    for cg in &active_cgroups {
        current_cgroups.insert(cg.clone());
        set_cgroup_limits(cg, "max 100000\n", "1000\n");
    }

    // Cgroups de aplicaciones en segundo plano
    for cg in &inactive_cgroups {
        current_cgroups.insert(cg.clone());
        if audio_cgroups.contains(cg) {
            set_cgroup_limits(cg, "60000 100000\n", "100\n");
        } else if heavy_cgroups.contains(cg) {
            set_cgroup_limits(cg, "20000 100000\n", "1\n");
        } else {
            set_cgroup_limits(cg, "30000 100000\n", "1\n");
        }
    }

    // Cgroup dedicado para background isolation de proyectos inactivos
    let bg_cg = get_user_background_cgroup();
    let app_cg = get_user_app_cgroup();
    if !bg_cg.exists() {
        let _ = fs::create_dir_all(&bg_cg);
    }
    set_cgroup_limits(&bg_cg, "15000 100000\n", "1\n");

    let bg_procs_file = bg_cg.join("cgroup.procs");
    let app_procs_file = app_cg.join("cgroup.procs");

    for &pid in &proj_inactive_all {
        if pid > 1 {
            let _ = fs::write(&bg_procs_file, format!("{}\n", pid));
        }
    }
    for &pid in &proj_active_all {
        if pid > 1 {
            let _ = fs::write(&app_procs_file, format!("{}\n", pid));
        }
    }

    if let Ok(mut guard) = MANAGED_CGROUPS.lock() {
        *guard = Some(current_cgroups);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Control de Planificacion de Procesos (Nice / I/O Priority)
    // ─────────────────────────────────────────────────────────────────────────
    let mut current_managed = HashSet::new();
    let mut states_guard = PID_STATES.lock().unwrap();
    if states_guard.is_none() {
        *states_guard = Some(HashMap::new());
    }
    let states_map = states_guard.as_mut().unwrap();

    let mut updated_count = 0;

    // Procesos activos -> SCHED_OTHER, nice 0, E/S prioritaria
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

    // Procesos inactivos -> Prioridades escalonadas
    for &pid in &inactive_all {
        current_managed.insert(pid);
        let has_audio = audio_all.contains(&pid);
        let is_heavy = heavy_all.contains(&pid);
        let is_proj_bg = proj_inactive_all.contains(&pid);

        let target_state = if has_audio {
            STATE_AUDIO_PROTECTED
        } else if is_heavy || is_proj_bg {
            STATE_HEAVY
        } else {
            STATE_INACTIVE
        };
        let prev = states_map.get(&pid).copied();

        if prev != Some(target_state) {
            unsafe {
                if has_audio {
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 0);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 2);
                    protected += 1;
                } else if is_heavy || is_proj_bg {
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 15);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 7);
                    throttled += 1;
                } else {
                    set_policy(pid, SCHED_OTHER);
                    set_nice(pid, 10);
                    set_ioprio(pid, IOPRIO_CLASS_BE, 6);
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

    // Gestionar prioridad de mpvpaper en segundo plano
    govern_wallmotion();

    if verbose && (ws_changed || updated_count > 0) {
        let elapsed = start.elapsed();
        println!(
            "[governor-rs] Workspace {} | Proyectos activos: {:?} | Actualizados: {} | Activos: {} | Fondo: {} | Audio: {} | Cgroups: {} ({:?})",
            active_ws.id,
            active_projects,
            updated_count,
            active_all.len(),
            throttled,
            protected,
            active_cgroups.len() + inactive_cgroups.len(),
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
                        | "closewindow" | "destroyworkspace" | "activewindow"
                        | "activewindowv2" => {
                            apply_governor(&dir, verbose);
                        }
                        _ => {}
                    }
                }
                Err(ref e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut =>
                {
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
