# Módulo de Scripts de Automatización, Mantenimiento y Rendimiento

Este directorio alberga los scripts ejecutables y utilidades del sistema para la gestión del hardware, control energético, corrección de controladores y actualización integral del sistema operativo.

---

## 1. Propósito & Alcance
Proveer automatización idempotente y defensiva para el mantenimiento de CachyOS / Arch Linux en un entorno ASUS Vivobook Go E1504GA (Intel Core i3-N305, 8 E-cores, 8 GB LPDDR5, Intel UHD 32EU).
El módulo garantiza que las actualizaciones del sistema operativo (kernel, pacman, AUR, Flatpak, runtimes) nunca sobrescriban ni degraden las optimizaciones de baja latencia y gestión de recursos aplicadas en el hardware.

---

## 2. Contratos & Métricas Técnicas

### Script Principal: `system-upgrade.sh`
- **Ruta destino:** `/home/omicron/dotfiles/scripts/system-upgrade.sh`
- **Enlace simbólico:** `/home/omicron/.local/bin/system-upgrade`
- **Permisos requeridos:** Permisos de usuario estándar con acceso a `sudo` (gestiona la elevación automáticamente mediante `sudo -v` y un loop en segundo plano). Si se ejecuta con `sudo`, conmuta a `$SUDO_USER` para las operaciones no-root (`yay`, `flatpak`, `rustup`, `bun`, `npm`, `spicetify`).
- **Complejidad algorítmica:** $O(N)$ sobre la lista de paquetes desactualizados y $O(1)$ sobre la verificación de invariantes de configuración.
- **Tiempo de ejecución típico:** 15 a 60 segundos dependiendo de los paquetes a descargar.
- **Consumo de recursos:** < 25 MB RAM durante la ejecución del script (excluyendo la compilación de paquetes AUR).

#### Interfaz de Línea de Comandos:
| Opción | Descripción |
| :--- | :--- |
| *(sin argumentos)* | Actualización desatendida completa (`-y`) con protección de rendimiento, limpieza de caché y menú interactivo de acción final (Reiniciar / Apagar / Permanecer). |
| `-r, --reboot` | Programa reinicio automático del sistema tras completar la actualización (con cuenta regresiva de 10s de seguridad). |
| `-s, --shutdown` (`-p, --poweroff`) | Programa apagado automático del sistema tras completar la actualización (con cuenta regresiva de 10s de seguridad). |
| `--stay` | Fuerza mantener el sistema encendido tras actualizar, sin reiniciar ni apagar y sin preguntas interactivas. |
| `-i, --interactive` | Modo interactivo con confirmación paso a paso en gestores de paquetes. |
| `--rate-mirrors` | Ejecuta `cachyos-rate-mirrors` para calibrar y ordenar espejos por velocidad antes de actualizar. |
| `--verify-only` | Salta la descarga de paquetes y comprueba/re-aplica las configuraciones de rendimiento activas. |
| `--backup-only` | Genera un snapshot criptográfico en `/var/backups/performance_snapshot_<TIMESTAMP>` sin actualizar. |
| `-h, --help` | Despliega el menú de ayuda y opciones disponibles. |

#### Paquetes y Runtimes Soportados:
1. **Sistema base y kernel:** `yay -Syu --needed` (repositorios CachyOS-v3, Arch core/extra/multilib).
2. **AUR:** Paquetes mantenidos por la comunidad mediante `yay`.
3. **Flatpak:** Aplicaciones y runtimes del sistema y del usuario (`flatpak update -y`).
4. **Rust:** Toolchains gestionados por `rustup` (`rustup update`).
5. **Bun:** Runtime (`bun upgrade`) y módulos globales (`bun update -g`).
6. **Node.js / NPM:** Paquetes globales (`npm update -g`).
7. **Spotify / Spicetify:** Re-parcheo y sincronización de temas (`spicetify upgrade && backup apply`).
8. **Google Antigravity CLI:** Actualización nativa de la IA y agentes (`agy update`).
9. **Mantenimiento pacman:** `paccache -rk2` (conserva 2 versiones para rollback) y `paccache -ruk0`.

---

## 3. Mapa de Entidades e Invariantes Protegidos

| Fichero de Configuración | Rol Técnico | Invariante Protegido |
| :--- | :--- | :--- |
| `/etc/systemd/zram-generator.conf` | Límite de compresión ZRAM | `zram-size = 12288` (12 GB), algoritmo `zstd`, `swap-priority = 100`. |
| `/etc/sysctl.d/99-local-performance.conf` | Parámetros de memoria y red | `vm.swappiness = 150`, `vm.stat_interval = 10`, `vm.compaction_proactiveness = 20`, `net.ipv4.tcp_congestion_control = bbr`. |
| `/etc/tmpfiles.d/thp.conf` | Transparent Huge Pages | `madvise` para enabled/defrag/shmem (evita fragmentación de 2MB en 8 GB RAM). |
| `/etc/modprobe.d/mt7921e.conf` | Estabilidad de Wi-Fi | `options mt7921e disable_aspm=1` (elimina pérdida de paquetes y latencia). |
| `/etc/modprobe.d/bluetooth.conf` | Mandos inalámbricos | `options bluetooth disable_ertm=1` (estabilidad en sincronización). |
| `/etc/NetworkManager/conf.d/default-wifi-powersave-off.conf` | Ahorro energético Wi-Fi | `wifi.powersave = 2` (potencia de transmisión fija sin caídas). |
| `/etc/udev/rules.d/99-power-state.rules` | Detección AC / Batería | Ejecuta `/usr/local/bin/power-state-manager` instantáneamente ante cambios de fuente. |
| `/etc/udev/rules.d/99-intel-gpu.rules` | Acceso a iGPU | Symlink `/dev/dri/intel-gpu`. |
| `/usr/local/bin/power-state-manager` | Regulador térmico y energético | CPU EPP `balance_performance` en AC vs `balance_power` en Batería; suelo iGPU 600 MHz; guardia térmica a 86 °C. |
| `~/.config/systemd/user/hypr-workspace-governor.service` | Gobernador de espacios | Regula CPU e I/O en tiempo real; aísla workspaces inactivos a `SCHED_IDLE` sin cortar audio. |
| `/etc/sudoers.d/99-power-state-manager` | Privilegios de ejecución | `%wheel ALL=(ALL) NOPASSWD: /usr/local/bin/power-state-manager`. |
| `~/.config/environment.d/` | Variables gráficas y memoria | iHD Media Driver, shader cache 4 GB en NVMe, redirección de caché Node. |
| `~/.config/brave-flags.conf` | Aceleración web | Aceleración por GPU y Wayland nativo. |
| `~/.config/spotify-flags.conf` | Aceleración Spotify | Flags Ozone Wayland, VA-API y rasterización por GPU. |

---

## 4. Decisiones de Diseño & Gotchas

1. **Aislamiento de Privilegios (`run_as_user` vs `run_as_root`):**
   - *Problema:* `yay` prohíbe terminantemente ejecutarse como `root`. Si un script de actualización se lanza con `sudo`, `yay` aborta de inmediato.
   - *Solución:* El script detecta si `id -u` es 0 y utiliza `sudo -u "$SUDO_USER" -H` para invocar `yay`, `flatpak`, `rustup`, `bun`, `npm` y `spicetify`, preservando los directorios de configuración del usuario sin corromper permisos de propiedad (`chown`).

2. **Snapshot Criptográfico Pre-Upgrade:**
   - Antes de modificar el sistema, se crea un directorio en `/var/backups/performance_snapshot_<TIMESTAMP>` con copias exactas y un archivo `manifest.sha256`. Si una actualización reemplaza algún fichero, el script lo detecta y lo restaura.

3. **Re-inyección de Spicetify:**
   - *Problema:* Cada vez que Spotify se actualiza mediante AUR o paquetes binarios, el ejecutable `/opt/spotify/spotify` se reemplaza por el binario virgen, rompiendo temas e impidiendo que inicie.
   - *Solución:* El script ejecuta automáticamente `spicetify upgrade` y `spicetify backup apply` tras la actualización de paquetes.

4. **Detección de Kernel y ZRAM:**
   - *Problema:* Tras actualizar `linux-cachyos`, los módulos compilados para el kernel viejo ya no se pueden cargar en caliente, y la ZRAM activa no puede redimensionarse en vivo si hay swap asignado.
   - *Solución:* El script compara `uname -r` con la versión de `linux-cachyos` en la base de datos de pacman y emite una alerta visual clara recomendando reiniciar el equipo.

---

## 5. Subsistema de Fondos Animados (`wallmotion`)
- **`animated-wallpaper-picker.sh`**: Genera filas TSV (`key\tlabel\timage`) en $O(N)$ desde `~/.config/wallmotion/library.json` para el carrusel de Quickshell, creando miniaturas JPG automáticas vía `ffmpeg` si faltan.
- **`animated-wallpaper-switcher.sh`**: Controlador de estados (`pick`, `apply <id>`, `current`, `add`, `delete <id>`, `is-running`, `toggle-stop [on|off]`). Gestiona la invocación IPC con Quickshell y conmuta `wallmotion` (`mpvpaper` con decodificación VAAPI por hardware, ~0% CPU).
- **Perfil de Cero Recursos y Máxima Calidad (60 FPS):**
  - **Decodificación hardware VDBOX ASIC:** `--hwdec=vaapi,auto-safe --hwdec-codecs=all` (0% impacto de CPU en H.264/HEVC 4K y 1080p).
  - **Cadencia fluida 60 FPS:** `--video-sync=desync --framedrop=vo` para entregar exactamente la tasa nativa del vídeo sin judder ni desfases respecto al refresco de pantalla.
  - **Downscaling 4K a 1080p sin coste de shaders:** `--profile=fast --scale=bilinear --cscale=bilinear --dscale=bilinear`. En ratio exacto 2:1 (3840x2160 -> 1920x1080), los samplers por hardware de la GPU Intel ejecutan un promediado 2x2 SSAA matemático impecable en un solo ciclo de textura, eliminando los 40 drops/s que provocaban los filtros polinomiales por software en shader.
  - **Buffer acotado:** `--demuxer-max-bytes=16MiB --demuxer-max-back-bytes=0 --cache=no` para mantener la RAM fija (~180 MB de espacio de trabajo de Wayland).
  - **Convivencia limpia de capas Wayland:** `wallmotion play` detiene `hyprpaper.service` para evitar colisión en Layer 0 (background) y ahorrar recursos. Al conmutar o detener el fondo animado (`toggle-stop off` o `wallpaper-switcher.sh apply`), `hyprpaper.service` se restaura de forma transparente e instantánea.
  - **Gestión de inactividad:** Se eliminaron las banderas `--auto-pause` de `mpvpaper` (que congelaban el fotograma bajo ventanas normales de Hyprland), delegando la suspensión por reposo a las reglas de `hypridle` (`~/.local/bin/wallmotion pause/resume`).
- **Atajo asignado:** `SUPER + SHIFT + T` (reemplaza el anterior conmutador de temas).

---

## 6. Gobernador de Espacios de Trabajo (`hypr-workspace-governor`)
- **`hypr-workspace-governor.py`**: Daemon ultraligero que conecta al socket IPC `.socket2.sock` de Hyprland para gobernar los recursos del sistema en base al espacio de trabajo visible.
- **Aislamiento en reposo:** Cuando un espacio de trabajo pasa a segundo plano, todos sus procesos e hilos internos se trasladan a la política del kernel `SCHED_IDLE`, prioridad de proceso `nice 19` y clase de E/S `IOPRIO_CLASS_IDLE`. La ventana en foco obtiene el 100% del tiempo de CPU e I/O sin contención.
- **Protección de audio en segundo plano:** Consulta periódicamente `pactl` para no reducir a `SCHED_IDLE` aplicaciones que estén reproduciendo sonido activamente (música o llamadas), evitando chasquidos o cortes.
- **`apply-kernel-optimizations.sh`**: Script administrativo para desplegar Transparent Huge Pages en `madvise`, `vm.stat_interval=10` y perfil térmico en un solo paso.

---

## 7. Cliente GeForce NOW de Baja Latencia (`geforce-now`)
- **Ruta destino:** `/home/omicron/dotfiles/scripts/geforce-now`
- **Enlace simbólico:** `/home/omicron/.local/bin/geforce-now`
- **Integración Desktop:** `~/.local/share/applications/geforcenow.desktop`
- **Propósito:** Lanzador dedicado y optimizado para streaming de juegos en la nube en Colombia (`America/Bogota`), eliminando bloqueos regionales y sobrecarga de Electron mediante motor WebApp acelerado por hardware.
- **Parámetros de Aceleración y Decodificación Hardware:**
  - `LIBVA_DRIVER_NAME=iHD` y `MESA_LOADER_DRIVER_OVERRIDE=iris` para forzar decodificación por hardware Intel QuickSync/VA-API directa en el chip Alder Lake-N.
  - `--ozone-platform=wayland` y `--use-gl=egl` para renderizado Wayland nativo con cero copias de memoria en buffer (`--enable-zero-copy`).
  - WebRTC con control de congestión BBR de baja latencia (`WebRtcHideLocalIpsWithMdns`).
  - Prioridad de proceso en tiempo real asignada por `ananicy-cpp` (`nice: -5`).
- **Opciones de Línea de Comandos:**
  - `geforce-now`: Acceso al portal de juego en la nube (`https://play.geforcenow.com`).
  - `geforce-now --digevo`: Conexión directa a DIGEVO Colombia (`https://geforcenow.digevo.com`), partner oficial de NVIDIA en la región con servidores locales.
  - `geforce-now --abya`: Conexión al partner oficial para el Cono Sur (`https://abya.gfn.am`).
  - `geforce-now --xbox`: Acceso alternativo para Xbox Cloud Gaming (Fortnite gratuito).



