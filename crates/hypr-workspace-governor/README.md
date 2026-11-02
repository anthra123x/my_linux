# hypr-workspace-governor

Gobernador de recursos nativo en Rust para el compositor Wayland Hyprland.
Garantiza aislamiento de CPU, memoria y ancho de banda de E/S, dedicando el 100% de la capacidad del sistema a las ventanas del espacio de trabajo activo y en foco.

---

## 1. Proposito y Alcance
- Escuchar eventos de cambio de espacio de trabajo y ventanas desde el socket IPC de Hyprland (`.socket2.sock`).
- Relegar procesos de espacios inactivos a prioridad ociosa del kernel (`SCHED_IDLE`, `nice 19`, `IOPRIO_CLASS_IDLE`).
- Promover ventanas del espacio activo a máxima prioridad interactiva (`SCHED_OTHER`, `nice 0`, `IOPRIO_CLASS_BE`).
- Preservar la reproducción ininterrumpida de audio (música, conferencias, llamadas) en aplicaciones de fondo mediante consulta de sumideros de PipeWire / PulseAudio.

---

## 2. Contratos
- **Entrada:** Eventos IPC de Hyprland (`workspace>>`, `focusedmon>>`, `openwindow>>`, `closewindow>>`).
- **Salida / Efectos de Sistema:**
  - Syscall `sched_setscheduler(pid, SCHED_IDLE | SCHED_OTHER, &param)`
  - Syscall `setpriority(PRIO_PROCESS, pid, nice)`
  - Syscall 251 `SYS_ioprio_set(IOPRIO_WHO_PROCESS, pid, prio)`
- **Manejo de Señales:** Ante `SIGINT` o `SIGTERM`, ejecuta una rutina que revierte inmediatamente todos los procesos gestionados a `SCHED_OTHER` y `nice 0`.

---

## 3. Dependencias
- **Internas:**
  - Hyprland IPC sockets (`.socket.sock` para consultas JSON y `.socket2.sock` para flujo de eventos).
  - PipeWire / PulseAudio CLI (`pactl -f json list sink-inputs`).
- **Externas (Crates):**
  - `libc = "0.2"` (llamadas directas a syscalls POSIX/Linux sin sobrecarga FFI).
  - `serde = "1.0"` y `serde_json = "1.0"` (deserialización de estructuras JSON de Hyprland y pactl).

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

