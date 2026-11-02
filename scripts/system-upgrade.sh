#!/usr/bin/env bash
# system-upgrade.sh
# ==============================================================================
# Script de actualización integral del sistema (CachyOS / Arch Linux)
#
# Actualiza TODO el software del sistema:
#   1. Sistema base, kernel de CachyOS, módulos y paquetes de repositorios oficiales (yay)
#   2. Paquetes del AUR (yay)
#   3. Paquetes Flatpak del sistema y usuario (flatpak update -y)
#   4. Toolchain de Rust (rustup update)
#   5. Runtimes y paquetes globales de Bun (bun upgrade && bun update -g)
#   6. Paquetes globales de Node.js / NPM (npm update -g)
#   7. Parcheo y sincronización de Spicetify para Spotify (spicetify upgrade & backup apply)
#   8. Limpieza inteligente de caché pacman (paccache -rk2 / paccache -ruk0)
#
# Guardia de Invariantes de Rendimiento (Zero Regression):
#   - Respaldo automático antes de iniciar (/var/backups/performance_snapshot_*)
#   - Verificación de integridad post-actualización
#   - Re-aplicación estricta de:
#       * Límite de ZRAM de 12 GB (12288 MiB en /etc/systemd/zram-generator.conf)
#       * Configuración sysctl de VM y red (swappiness=150, BBR, vfs_cache_pressure=75)
#       * Desactivación de PCIe ASPM en Wi-Fi MediaTek MT7902/MT7921 (mt7921e disable_aspm=1)
#       * Desactivación de ahorro de energía Wi-Fi en NetworkManager (wifi.powersave = 2)
#       * Desactivación de ERTM en Bluetooth para mandos inalámbricos
#       * Perfiles de energía dinámicos (power-state-manager en AC/Batería y guardia térmica)
#       * Reglas udev de energía y GPU Intel
#       * Flags de aceleración gráfica en Brave, Spotify y variables de entorno Wayland
# ==============================================================================

set -euo pipefail

# Colores y formatos
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[1;35m'
RESET='\033[0m'

header() { printf "\n${BOLD}${MAGENTA}======================================================================${RESET}\n${BOLD}${CYAN}  %b${RESET}\n${BOLD}${MAGENTA}======================================================================${RESET}\n" "$1"; }
log()    { printf "${CYAN}==>${RESET} ${BOLD}%b${RESET}\n" "$1"; }
ok()     { printf "    ${GREEN}[OK]${RESET} %b\n" "$1"; }
warn()   { printf "    ${YELLOW}[AVISO]${RESET} %b\n" "$1"; }
err()    { printf "    ${RED}[ERROR]${RESET} %b\n" "$1" >&2; }
die()    { printf "\n${RED}${BOLD}ERROR CRÍTICO:${RESET} %b\n\n" "$1" >&2; exit 1; }

# Determinar usuario real (no root si se ejecutó con sudo)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

run_as_user() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" -H "$@"
  else
    "$@"
  fi
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

usage() {
  cat << EOF
Uso: $(basename "$0") [OPCIONES]

Actualiza todo el sistema operativo (kernel, pacman, AUR, flatpaks, runtimes y toolchains)
garantizando la preservación estricta de todas las configuraciones de rendimiento.

Opciones:
  -y, --noconfirm     Actualización desatendida sin confirmaciones interactivas (por defecto)
  -i, --interactive   Preguntar confirmación en cada etapa de actualización
  -r, --reboot        Reiniciar el equipo automáticamente tras finalizar la actualización
  -s, --shutdown      Apagar el equipo automáticamente tras finalizar la actualización (-p, --poweroff)
  --stay              Mantener el sistema encendido sin reiniciar ni apagar
  --rate-mirrors      Ejecutar 'cachyos-rate-mirrors' antes de actualizar (optimiza espejos)
  --verify-only       Verificar y re-aplicar configuraciones de rendimiento sin actualizar paquetes
  --backup-only       Generar únicamente el snapshot de respaldo de configuraciones
  -h, --help          Muestra esta ayuda y sale

Ejemplos:
  system-upgrade              # Actualización completa (pregunta acción final si es interactivo)
  system-upgrade -r           # Actualizar todo y reiniciar automáticamente
  system-upgrade -s           # Actualizar todo y apagar el equipo automáticamente
  system-upgrade --verify-only # Comprueba y refuerza los límites de ZRAM y sysctl
EOF
}

# Parámetros por defecto
NON_INTERACTIVE=true
RATE_MIRRORS=false
VERIFY_ONLY=false
BACKUP_ONLY=false
POST_ACTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--noconfirm|--no-confirm)
      NON_INTERACTIVE=true
      shift
      ;;
    -i|--interactive)
      NON_INTERACTIVE=false
      shift
      ;;
    -r|--reboot)
      POST_ACTION="reboot"
      shift
      ;;
    -s|--shutdown|-p|--poweroff)
      POST_ACTION="poweroff"
      shift
      ;;
    --stay)
      POST_ACTION="stay"
      shift
      ;;
    --rate-mirrors)
      RATE_MIRRORS=true
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
    --backup-only)
      BACKUP_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Opción desconocida: $1"
      usage
      exit 1
      ;;
  esac
done

# -------------------------------------------------------------------------
# Fase 0: Validación de Privilegios y Elevación
# -------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  # Solicitar credenciales sudo temprano si no se ejecutó como root
  log "Comprobando permisos de administrador..."
  sudo -v || die "Se requieren permisos de administrador (sudo) para actualizar el sistema."
  # Mantener vivo el token de sudo en segundo plano
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT
fi

# -------------------------------------------------------------------------
# Selección de Acción Post-Actualización (Reinicio o Apagado)
# -------------------------------------------------------------------------
if [ -z "$POST_ACTION" ] && [ "$VERIFY_ONLY" = false ] && [ "$BACKUP_ONLY" = false ]; then
  if [ -t 0 ]; then
    header "ACCIÓN POST-ACTUALIZACIÓN"
    printf "Selecciona qué deseas que haga el sistema al terminar de actualizar:\n"
    printf "  ${BOLD}1)${RESET} ${CYAN}Reiniciar el equipo${RESET} (Reboot - recomendado tras actualizar kernel)\n"
    printf "  ${BOLD}2)${RESET} ${MAGENTA}Apagar el equipo${RESET} (Power off / Shutdown)\n"
    printf "  ${BOLD}3)${RESET} ${GREEN}Mantener encendido${RESET} (Salir al terminal)\n\n"
    read -t 15 -p "Selecciona una opción [1-3] (15 segundos para responder, por defecto 3): " ACTION_SELECTION || ACTION_SELECTION="3"
    printf "\n"
    case "$ACTION_SELECTION" in
      1|r|R)
        POST_ACTION="reboot"
        ok "Opción seleccionada: Se REINICIARÁ el equipo al finalizar."
        ;;
      2|a|A|s|S|p|P)
        POST_ACTION="poweroff"
        ok "Opción seleccionada: Se APAGARÁ el equipo al finalizar."
        ;;
      *)
        POST_ACTION="stay"
        ok "Opción seleccionada: El sistema PERMANECERÁ ENCENDIDO al finalizar."
        ;;
    esac
  else
    POST_ACTION="stay"
  fi
fi

# -------------------------------------------------------------------------
# Fase 1: Comprobaciones Previas (Pre-flight checks)
# -------------------------------------------------------------------------
header "FASE 1: COMPROBACIONES PREVIAS DEL SISTEMA"

# 1.1 Conectividad a internet
log "Comprobando conectividad a internet..."
check_online() {
  ping -c 1 -W 2 1.1.1.1 &>/dev/null || \
  ping -c 1 -W 2 8.8.8.8 &>/dev/null || \
  curl -sI --max-time 3 https://archlinux.org &>/dev/null || \
  curl -sI --max-time 3 https://cachyos.org &>/dev/null
}

IS_ONLINE=false
for attempt in 1 2 3; do
  if check_online; then
    IS_ONLINE=true
    break
  fi
  sleep 1
done

if [ "$IS_ONLINE" = false ]; then
  die "No hay conexión a internet detectada. Por favor verifica tu conexión antes de continuar."
fi
ok "Conexión a internet verificada"

# 1.2 Bloqueo de base de datos pacman
log "Comprobando base de datos de pacman..."
if [ -f /var/lib/pacman/db.lck ]; then
  die "El archivo /var/lib/pacman/db.lck existe. Otra instancia de pacman/yay está ejecutándose o se cerró abruptamente."
fi
ok "Base de datos de pacman desbloqueada"

# 1.3 Espacio en disco disponible
log "Comprobando espacio libre en partición raíz (/)..."
FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')
if [ "$FREE_SPACE_MB" -lt 2048 ]; then
  warn "Espacio libre bajo en /: ${FREE_SPACE_MB} MB. Se recomienda tener al menos 2048 MB libres."
else
  ok "Espacio suficiente en disco: ${FREE_SPACE_MB} MB libres en /"
fi

# -------------------------------------------------------------------------
# Fase 2: Snapshot de Respaldo de Configuraciones de Rendimiento
# -------------------------------------------------------------------------
header "FASE 2: SNAPSHOT DE RESPALDO DE RENDIMIENTO"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/performance_snapshot_$TIMESTAMP"
run_as_root mkdir -p "$BACKUP_DIR"

log "Generando snapshot de configuraciones críticas en $BACKUP_DIR..."

PERF_FILES=(
  "/etc/systemd/zram-generator.conf"
  "/etc/sysctl.d/99-local-performance.conf"
  "/etc/modprobe.d/mt7921e.conf"
  "/etc/modprobe.d/bluetooth.conf"
  "/etc/NetworkManager/conf.d/default-wifi-powersave-off.conf"
  "/etc/udev/rules.d/99-power-state.rules"
  "/etc/udev/rules.d/99-intel-gpu.rules"
  "/etc/sudoers.d/99-power-state-manager"
  "/usr/local/bin/power-state-manager"
  "/etc/systemd/system/power-state-manager.service"
  "/etc/systemd/system/power-state-manager-monitor.service"
  "/etc/systemd/system/power-state-manager-monitor.timer"
  "$TARGET_HOME/.config/brave-flags.conf"
  "$TARGET_HOME/.config/spotify-flags.conf"
  "$TARGET_HOME/.config/hypr/looknfeel.lua"
)

MANIFEST_FILE="$BACKUP_DIR/manifest.sha256"
: > /tmp/manifest_temp

for file in "${PERF_FILES[@]}"; do
  if run_as_root test -f "$file"; then
    DEST_DIR="$BACKUP_DIR/$(dirname "$file")"
    run_as_root mkdir -p "$DEST_DIR"
    run_as_root cp -p "$file" "$DEST_DIR/"
    run_as_root sha256sum "$file" >> /tmp/manifest_temp 2>/dev/null || true
    ok "Respaldado: $file"
  else
    warn "Archivo no encontrado (se creará en verificación): $file"
  fi
done

# Respaldar directorio environment.d completo si existe
if [ -d "$TARGET_HOME/.config/environment.d" ]; then
  DEST_DIR="$BACKUP_DIR/$TARGET_HOME/.config"
  run_as_root mkdir -p "$DEST_DIR"
  run_as_root cp -rp "$TARGET_HOME/.config/environment.d" "$DEST_DIR/"
  find "$TARGET_HOME/.config/environment.d" -type f -exec sha256sum {} + >> /tmp/manifest_temp 2>/dev/null || true
  ok "Respaldado: $TARGET_HOME/.config/environment.d/"
fi

run_as_root mv /tmp/manifest_temp "$MANIFEST_FILE"
run_as_root chmod 600 "$MANIFEST_FILE"
ok "Manifiesto de integridad criptográfico generado en $MANIFEST_FILE"

if [ "$BACKUP_ONLY" = true ]; then
  log "Modo --backup-only completado con éxito."
  exit 0
fi

# -------------------------------------------------------------------------
# Fase 3: Actualización Integral de Software y Kernel
# -------------------------------------------------------------------------
if [ "$VERIFY_ONLY" = false ]; then
  header "FASE 3: ACTUALIZACIÓN INTEGRAL DEL SISTEMA"

  # 3.0 Optimización de espejos (opcional)
  if [ "$RATE_MIRRORS" = true ]; then
    if command -v cachyos-rate-mirrors &>/dev/null; then
      log "Optimizando espejos de descarga con cachyos-rate-mirrors..."
      run_as_root cachyos-rate-mirrors || warn "Fallo al calificar espejos, continuando con espejos existentes."
    fi
  fi

  # Registrar versión de kernel actual antes de actualizar
  PREV_KERNEL=$(uname -r)
  log "Versión de kernel en ejecución: $PREV_KERNEL"

  # 3.1 Paquetes del Sistema, Kernel y AUR mediante yay
  if command -v yay &>/dev/null; then
    log "Actualizando paquetes de CachyOS, Arch Linux y AUR..."
    YAY_ARGS=("-Syu" "--needed")
    if [ "$NON_INTERACTIVE" = true ]; then
      YAY_ARGS+=("--noconfirm")
    fi
    
    # yay debe ejecutarse como usuario no-root
    run_as_user yay "${YAY_ARGS[@]}"
    ok "Paquetes oficiales y AUR actualizados"
  else
    warn "yay no está instalado; recurriendo a pacman..."
    PACMAN_ARGS=("-Syu" "--needed")
    if [ "$NON_INTERACTIVE" = true ]; then
      PACMAN_ARGS+=("--noconfirm")
    fi
    run_as_root pacman "${PACMAN_ARGS[@]}"
    ok "Paquetes de repositorios oficiales actualizados"
  fi

  # 3.2 Paquetes Flatpak (Sistema y Usuario)
  if command -v flatpak &>/dev/null; then
    log "Actualizando aplicaciones y runtimes Flatpak..."
    run_as_user flatpak update -y || warn "Advertencia durante actualización de Flatpak de usuario"
    run_as_root flatpak update -y || warn "Advertencia durante actualización de Flatpak del sistema"
    ok "Flatpaks actualizados"
  fi

  # 3.3 Toolchains de Rust (rustup)
  RUSTUP_BIN=""
  if [ -x "$TARGET_HOME/.cargo/bin/rustup" ]; then
    RUSTUP_BIN="$TARGET_HOME/.cargo/bin/rustup"
  elif command -v rustup &>/dev/null; then
    RUSTUP_BIN=$(command -v rustup)
  fi

  if [ -n "$RUSTUP_BIN" ]; then
    log "Actualizando toolchains de Rust ($RUSTUP_BIN)..."
    run_as_user "$RUSTUP_BIN" update || warn "No se pudo actualizar el toolchain de Rust"
    ok "Rustup toolchains actualizados"
  fi

  # 3.4 Runtime de Bun y paquetes globales
  BUN_BIN=""
  if [ -x "$TARGET_HOME/.local/bin/bun" ]; then
    BUN_BIN="$TARGET_HOME/.local/bin/bun"
  elif [ -x "$TARGET_HOME/.bun/bin/bun" ]; then
    BUN_BIN="$TARGET_HOME/.bun/bin/bun"
  elif command -v bun &>/dev/null; then
    BUN_BIN=$(command -v bun)
  fi

  if [ -n "$BUN_BIN" ]; then
    log "Actualizando runtime de Bun y paquetes globales..."
    run_as_user "$BUN_BIN" upgrade || warn "No se pudo actualizar el binario de Bun"
    if [ -d "$TARGET_HOME/.bun/install/global" ]; then
      run_as_user "$BUN_BIN" update -g || warn "No se pudieron actualizar paquetes globales de Bun"
    fi
    ok "Bun actualizado"
  fi

  # 3.5 Paquetes globales de Node.js / NPM
  NPM_BIN=""
  if [ -x "$TARGET_HOME/.local/bin/npm" ]; then
    NPM_BIN="$TARGET_HOME/.local/bin/npm"
  elif command -v npm &>/dev/null; then
    NPM_BIN=$(command -v npm)
  fi

  if [ -n "$NPM_BIN" ]; then
    log "Actualizando paquetes globales de NPM..."
    run_as_user "$NPM_BIN" update -g || warn "No se pudieron actualizar paquetes globales de NPM"
    ok "Paquetes globales de NPM actualizados"
  fi

  # 3.6 Spicetify / Spotify: Re-inyección de parches tras actualización
  SPICETIFY_BIN=""
  if [ -x "$TARGET_HOME/.spicetify/spicetify" ]; then
    SPICETIFY_BIN="$TARGET_HOME/.spicetify/spicetify"
  elif command -v spicetify &>/dev/null; then
    SPICETIFY_BIN=$(command -v spicetify)
  fi

  if [ -n "$SPICETIFY_BIN" ] && command -v spotify &>/dev/null; then
    log "Actualizando y re-aplicando temas de Spicetify para Spotify..."
    run_as_user "$SPICETIFY_BIN" upgrade || true
    run_as_user "$SPICETIFY_BIN" backup apply || warn "Spicetify backup apply devolvió código no-cero; continuando"
    ok "Spicetify re-sincronizado con Spotify"
  fi

  # 3.7 Google Antigravity CLI (agy)
  AGY_BIN=""
  if [ -x "$TARGET_HOME/.local/bin/agy" ]; then
    AGY_BIN="$TARGET_HOME/.local/bin/agy"
  elif command -v agy &>/dev/null; then
    AGY_BIN=$(command -v agy)
  fi

  if [ -n "$AGY_BIN" ]; then
    log "Actualizando Google Antigravity CLI ($AGY_BIN)..."
    run_as_user "$AGY_BIN" update || warn "No se pudo actualizar agy mediante agy update"
    ok "Google Antigravity CLI verificado/actualizado"
  fi

  # 3.8 Mantenimiento y Limpieza de Caché de Pacman
  if command -v paccache &>/dev/null; then
    log "Limpiando paquetes antiguos de la caché de pacman (conservando las últimas 2 versiones)..."
    run_as_root paccache -rk2 || true
    log "Eliminando paquetes desinstalados de la caché..."
    run_as_root paccache -ruk0 || true
    ok "Caché de pacman optimizada"
  fi
fi

# -------------------------------------------------------------------------
# Fase 4: Guardia y Re-aplicación Estricta de Configuraciones de Rendimiento
# -------------------------------------------------------------------------
header "FASE 4: GUARDIA DE PRESERVACIÓN DE RENDIMIENTO"

log "Verificando y reforzando invariantes de rendimiento..."

# 4.1 Límite de ZRAM a 3 GB (3072 MiB)
ZRAM_CONF="/etc/systemd/zram-generator.conf"
log "Comprobando $ZRAM_CONF..."
run_as_root mkdir -p /etc/systemd
if [ ! -f "$ZRAM_CONF" ] || ! grep -q "zram-size = 12288" "$ZRAM_CONF"; then
  warn "Límite de ZRAM desalineado o ausente. Re-escribiendo configuración óptima (12 GB)..."
  run_as_root tee "$ZRAM_CONF" > /dev/null << 'EOF'
# Configuracion optimizada de ZRAM para 8 GB RAM (ASUS Vivobook Go E1504GA)
# 12 GB (12288 MiB) para absorber multitarea extrema (Brave 20+ tabs + 2 IDEs + Spotify + mpvpaper) en RAM comprimida (zstd).
# Con ratio zstd ~3.3:1, 12 GB ocupan solo ~3.6 GB de RAM física, evitando al 100% el desbordamiento al NVMe (swapfile).
[zram0]
zram-size = 12288
compression-algorithm = zstd
swap-priority = 100
EOF
  run_as_root chmod 644 "$ZRAM_CONF"
  ok "ZRAM asegurado en 12 GB (12288 MiB)"
else
  ok "ZRAM verificado: límite óptimo de 12 GB intacto"
fi

# 4.2 Parámetros sysctl (swappiness=150, BBR, vfs_cache_pressure=75)
SYSCTL_CONF="/etc/sysctl.d/99-local-performance.conf"
log "Comprobando $SYSCTL_CONF..."
run_as_root mkdir -p /etc/sysctl.d
if [ ! -f "$SYSCTL_CONF" ] || ! grep -q "vm.swappiness = 150" "$SYSCTL_CONF" || ! grep -q "tcp_congestion_control = bbr" "$SYSCTL_CONF"; then
  warn "Configuración sysctl desalineada. Re-aplicando ajustes de baja latencia y RAM de 8 GB..."
  run_as_root tee "$SYSCTL_CONF" > /dev/null << 'EOF'
# Ajustes de memoria para un equipo de 8 GB.
#
# swappiness=150 se mantiene a proposito: con zram delante del swapfile, el
# kernel manda lo caliente a zram (RAM comprimida, rapidisima) y lo frio al
# swapfile. Eso es lo que hace que 8 GB rendan como 12.
#
# SE CAMBIO min_free_kbytes de 131072 a 65536. Con 128 MB de reserva forzada
# sobre 7,4 GB, el kernel empezaba a reclamar tan temprano que empujaba el
# sistema contra el umbral de OOM en lugar de alejarse de el. 64 MB sigue
# siendo holgado y deja margen.
vm.vfs_cache_pressure = 75
vm.min_free_kbytes = 65536
vm.swappiness = 150
vm.page-cluster = 0

# Control de congestion TCP BBR (navegacion web rapida y menor bufferbloat)
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
EOF
  run_as_root chmod 644 "$SYSCTL_CONF"
fi
run_as_root sysctl --system > /dev/null 2>&1
ok "Parámetros sysctl activos en el kernel: swappiness=150, vfs_cache_pressure=75, TCP BBR"

# 4.3 Wi-Fi MediaTek MT7902/MT7921: Desactivar PCIe ASPM (Cero pérdida de paquetes)
MT7921_CONF="/etc/modprobe.d/mt7921e.conf"
log "Comprobando $MT7921_CONF..."
run_as_root mkdir -p /etc/modprobe.d
if [ ! -f "$MT7921_CONF" ] || ! grep -q "disable_aspm=1" "$MT7921_CONF"; then
  warn "Modprobe mt7921e sin disable_aspm=1. Re-aplicando..."
  run_as_root tee "$MT7921_CONF" > /dev/null << 'EOF'
# Desactiva PCIe ASPM en MediaTek MT7902/MT7921 para eliminar caidas de potencia y micro-cortes
options mt7921e disable_aspm=1
EOF
  run_as_root chmod 644 "$MT7921_CONF"
  ok "PCIe ASPM desactivado para MediaTek mt7921e"
else
  ok "Estabilidad Wi-Fi verificada: disable_aspm=1 en mt7921e"
fi

# 4.4 Bluetooth ERTM
BT_CONF="/etc/modprobe.d/bluetooth.conf"
log "Comprobando $BT_CONF..."
if [ ! -f "$BT_CONF" ] || ! grep -q "disable_ertm=1" "$BT_CONF"; then
  run_as_root tee "$BT_CONF" > /dev/null << 'EOF'
# Desactiva ERTM para compatibilidad total con mandos inalambricos (Xbox, DualShock, etc.)
options bluetooth disable_ertm=1
EOF
  run_as_root chmod 644 "$BT_CONF"
  ok "Bluetooth ERTM desactivado"
else
  ok "Bluetooth ERTM verificado"
fi

# 4.5 Wi-Fi Power Save en NetworkManager
NM_CONF="/etc/NetworkManager/conf.d/default-wifi-powersave-off.conf"
log "Comprobando $NM_CONF..."
run_as_root mkdir -p /etc/NetworkManager/conf.d
if [ ! -f "$NM_CONF" ] || ! grep -q "wifi.powersave = 2" "$NM_CONF"; then
  warn "Ahorro de energía de Wi-Fi activado en NetworkManager. Forzando wifi.powersave=2..."
  run_as_root tee "$NM_CONF" > /dev/null << 'EOF'
[connection]
wifi.powersave = 2
EOF
  run_as_root chmod 644 "$NM_CONF"
  run_as_root systemctl reload NetworkManager 2>/dev/null || true
  ok "Ahorro de energía de Wi-Fi desactivado permanentemente"
else
  ok "Ahorro de energía de Wi-Fi verificado: desactivado (wifi.powersave = 2)"
fi

# 4.6 Reglas udev de distribución de energía y GPU Intel
UDEV_PWR="/etc/udev/rules.d/99-power-state.rules"
UDEV_GPU="/etc/udev/rules.d/99-intel-gpu.rules"
log "Comprobando reglas udev..."
run_as_root mkdir -p /etc/udev/rules.d

if [ ! -f "$UDEV_PWR" ]; then
  run_as_root tee "$UDEV_PWR" > /dev/null << 'EOF'
# Aplica el perfil de rendimiento en el instante en que cambia la
# alimentacion, sin esperar al siguiente arranque.
ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", \
    RUN+="/usr/local/bin/power-state-manager ac"

ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", \
    RUN+="/usr/local/bin/power-state-manager battery"
EOF
  run_as_root chmod 644 "$UDEV_PWR"
fi

if [ ! -f "$UDEV_GPU" ]; then
  run_as_root tee "$UDEV_GPU" > /dev/null << 'EOF'
KERNEL=="card[0-9]*", KERNELS=="0000:00:02.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/intel-gpu"
EOF
  run_as_root chmod 644 "$UDEV_GPU"
fi

run_as_root udevadm control --reload-rules
run_as_root udevadm trigger
ok "Reglas udev recargadas y sincronizadas"

# 4.7 power-state-manager y servicios systemd
log "Comprobando gestor de perfiles térmicos y energéticos..."
if [ -f "/usr/local/bin/power-state-manager" ]; then
  run_as_root chmod 755 "/usr/local/bin/power-state-manager"

  # Verificar y blindar regla sudoers para evitar peticiones de contraseña en power-state-manager
  SUDOERS_PWR="/etc/sudoers.d/99-power-state-manager"
  if ! run_as_root test -f "$SUDOERS_PWR"; then
    echo "%wheel ALL=(ALL) NOPASSWD: /usr/local/bin/power-state-manager" | run_as_root tee "$SUDOERS_PWR" > /dev/null
    run_as_root chmod 440 "$SUDOERS_PWR"
    ok "Regla sudoers para power-state-manager restablecida"
  fi

  run_as_root systemctl daemon-reload
  run_as_root systemctl enable --now power-state-manager.service power-state-manager-monitor.timer > /dev/null 2>&1 || true
  run_as_root /usr/local/bin/power-state-manager apply > /dev/null 2>&1 || true
  ok "power-state-manager activo y perfil energético aplicado según fuente de poder actual"
else
  warn "/usr/local/bin/power-state-manager no encontrado"
fi

# 4.8 Integridad de configuraciones a nivel de usuario
log "Verificando flags de hardware y entorno de usuario..."
for conf in "$TARGET_HOME/.config/brave-flags.conf" "$TARGET_HOME/.config/spotify-flags.conf"; do
  if [ -f "$conf" ]; then
    ok "Flags presentes: $(basename "$conf")"
  fi
done

# 4.9 Inspección de archivos .pacnew
log "Examinando posibles archivos de configuración nuevos (.pacnew)..."
PACNEWS=$(find /etc -name "*.pacnew" 2>/dev/null || true)
if [ -n "$PACNEWS" ]; then
  warn "Se detectaron archivos .pacnew en /etc:"
  echo "$PACNEWS" | sed 's/^/      -> /'
  warn "Tus archivos de rendimiento están blindados, pero revisa si otros paquetes requieren merge manual."
else
  ok "No se encontraron conflictos de configuración .pacnew en /etc"
fi

# -------------------------------------------------------------------------
# Fase 5: Reporte de Kernel y Cierre
# -------------------------------------------------------------------------
header "FASE 5: RESUMEN Y ESTADO FINAL"

CURR_KERNEL=$(uname -r)
NEW_KERNEL=$(pacman -Q linux-cachyos 2>/dev/null | awk '{print $2}' || true)

printf "\n"
ok "Actualización de sistema y software finalizada con éxito."
ok "Todas las configuraciones de rendimiento fueron verificadas y reforzadas."
ok "Snapshot de respaldo disponible en: ${BOLD}${BACKUP_DIR}${RESET}"

if [ -n "$NEW_KERNEL" ]; then
  if [[ "$CURR_KERNEL" != *"$NEW_KERNEL"* ]]; then
    printf "${BOLD}${YELLOW}======================================================================${RESET}\n"
    printf "${BOLD}${YELLOW}  [!] ACTUALIZACIÓN DE KERNEL DETECTADA: %s -> %s${RESET}\n" "$CURR_KERNEL" "$NEW_KERNEL"
    printf "${BOLD}${YELLOW}  Se recomienda REINICIAR el equipo para arrancar con el nuevo kernel${RESET}\n"
    printf "${BOLD}${YELLOW}  y aplicar el límite definitivo de ZRAM (3 GB).${RESET}\n"
    printf "${BOLD}${YELLOW}======================================================================${RESET}\n\n"
  else
    ok "El kernel en ejecución coincide con la última versión instalada ($CURR_KERNEL)."
  fi
fi

# -------------------------------------------------------------------------
# Fase 6: Ejecución de Acción Post-Actualización (Reinicio o Apagado)
# -------------------------------------------------------------------------
if [ "$VERIFY_ONLY" = false ] && [ "$BACKUP_ONLY" = false ]; then
  case "${POST_ACTION:-stay}" in
    reboot)
      header "REINICIANDO EL SISTEMA"
      log "Reiniciando el equipo en 10 segundos... (Presiona Ctrl+C para cancelar)"
      for i in {10..1}; do
        printf "  -> Reiniciando en %d segundos...\r" "$i"
        sleep 1
      done
      printf "\n"
      run_as_root systemctl reboot
      ;;
    poweroff)
      header "APAGANDO EL SISTEMA"
      log "Apagando el equipo en 10 segundos... (Presiona Ctrl+C para cancelar)"
      for i in {10..1}; do
        printf "  -> Apagando en %d segundos...\r" "$i"
        sleep 1
      done
      printf "\n"
      run_as_root systemctl poweroff
      ;;
    stay)
      if [ -t 0 ] && [ -n "$NEW_KERNEL" ] && [[ "$CURR_KERNEL" != *"$NEW_KERNEL"* ]]; then
        read -t 20 -p "¿Deseas reiniciar el equipo ahora para aplicar el nuevo kernel? [s/N] (20s): " PROMPT_REBOOT || PROMPT_REBOOT="N"
        printf "\n"
        case "$PROMPT_REBOOT" in
          s|S|y|Y|si|sí|yes)
            log "Reiniciando..."
            run_as_root systemctl reboot
            ;;
          *)
            ok "Permaneciendo en el sistema. Recuerda reiniciar más tarde."
            ;;
        esac
      fi
      ;;
  esac
fi
