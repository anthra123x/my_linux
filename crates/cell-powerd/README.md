# cell-powerd

Daemon nativo en Rust para gestion energetica, deteccion de fuente de alimentacion y control de umbrales criticos de descarga en Cell OS.

---

## 1. Proposito y Alcance
- Reemplazar los scripts periodicos de Bash (`battery-monitor.sh`) y llamadas costosas a `upower` y `awk`.
- Monitorear el estado de conexion a la red electrica (AC) y niveles de bateria directamente desde sysfs (`/sys/class/power_supply/`) en microsegundos sin fork/exec.
- Sincronizar perfiles de energia con `powerprofilesctl` y `/usr/local/bin/power-state-manager`.
- Atenuar preventivamente el brillo de pantalla ante umbrales de descarga criticos (20%, 15%, 10%, 5%, 3%) y restaurarlo al reconectar el cargador.

---

## 2. Contratos
- **Entrada:** Lectura directa de `/sys/class/power_supply/` (ficheros `online`, `capacity`, `status`).
- **Salida:**
  - Invocacion de `powerprofilesctl set [performance|balanced|power-saver]`.
  - Invocacion de `sudo -n /usr/local/bin/power-state-manager [ac|battery]`.
  - Notificaciones de escritorio mediante `notify-send`.
  - Ajuste de brillo via `brightnessctl`.
- **Senales:** Soporte nativo para parada limpia ante `SIGINT` o `SIGTERM`.

---

## 3. Dependencias
- **Internas:**
  - `powerprofilesctl` (daemon de perfiles de energia de freedesktop).
  - `brightnessctl` (regulador de retroiluminacion).
  - `/usr/local/bin/power-state-manager` (regulador termico ACPI).
- **Externas (Crates):**
  - `libc = "0.2"` (senales POSIX nativas).

---

## 4. Mapa de Archivos
- `Cargo.toml`: Manifiesto y configuracion de optimizacion de tamano y LTO.
- `src/main.rs`: Logica de ciclo de vida del daemon y lectura de sysfs.
- `README.md`: Documentacion tecnica y contratos del modulo.

---

## 5. Decisiones y Gotchas
1. **Lectura directa de sysfs vs D-Bus:** Consultar `/sys/class/power_supply/` evita la latencia y sobrecarga de invocar el demonio `upower` a traves del bus de mensajes, permitiendo verificaciones en nanosegundos con 0% de CPU.
2. **Idempotencia de Notificaciones:** Mantiene un registro en memoria del ultimo umbral cruzado para no saturar al usuario con avisos repetidos a menos que el nivel descienda a un nuevo escalon critico.

---

## 6. Como Verificar
```bash
# Compilar binario en modo release
cargo build --release

# Probar ejecucion directa
./target/release/cell-powerd
```
