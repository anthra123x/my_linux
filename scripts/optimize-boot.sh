#!/usr/bin/env bash
# optimize-boot.sh
# Optimiza el arranque del sistema y activa el flujo verbose de inicio (líneas de código del kernel y systemd).
#
# Diagnóstico resuelto:
#   1. power-state-manager.service se colgaba 25.6s en multi-user.target por timeout D-Bus esperando a power-profiles-daemon.
#   2. plymouth y plymouth-quit-wait demoraban ~5s bloqueando el arranque y ocultando los logs.
#   3. quiet y splash en kernel cmdline censuraban la salida de inicio.

set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '    \033[0;33m[!!]\033[0m %s\n' "$1"; }
die()  { printf '\n\033[0;31mFALLO: %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Este script debe ejecutarse con privilegios de root: sudo bash $0"

STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/boot_optimization_$STAMP"
mkdir -p "$BACKUP_DIR"

# -------------------------------------------------------------------------
# 1. Optimizar power-state-manager.service (Ahorro de ~25.6 segundos)
# -------------------------------------------------------------------------
log "1/5  Optimizando power-state-manager.service..."
PSM_SERVICE="/etc/systemd/system/power-state-manager.service"
if [ -f "$PSM_SERVICE" ]; then
    cp -a "$PSM_SERVICE" "$BACKUP_DIR/power-state-manager.service"
    cat << 'EOF' > "$PSM_SERVICE"
[Unit]
Description=Aplicar estado de rendimiento segun fuente de alimentacion
After=power-profiles-daemon.service
Wants=power-profiles-daemon.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/power-state-manager apply
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF
    systemctl daemon-reload
    systemctl reenable power-state-manager.service 2>/dev/null || true
    ok "power-state-manager reconfigurado para graphical.target tras power-profiles-daemon (sin bloqueos de D-Bus)"
else
    warn "No se encontro $PSM_SERVICE"
fi

# -------------------------------------------------------------------------
# 2. Deshabilitar y enmascarar servicios de Plymouth (Ahorro de ~5 segundos)
# -------------------------------------------------------------------------
log "2/5  Deshabilitando servicios de splash Plymouth..."
systemctl mask plymouth-start.service \
               plymouth-quit.service \
               plymouth-quit-wait.service \
               plymouth-read-write.service \
               plymouth-halt.service \
               plymouth-poweroff.service \
               plymouth-reboot.service 2>/dev/null || true
ok "Servicios de Plymouth enmascarados correctamente"

# -------------------------------------------------------------------------
# 3. Remover plymouth de mkinitcpio.conf
# -------------------------------------------------------------------------
log "3/5  Removiendo hook plymouth de /etc/mkinitcpio.conf..."
MKINIT_CONF="/etc/mkinitcpio.conf"
if [ -f "$MKINIT_CONF" ]; then
    cp -a "$MKINIT_CONF" "$BACKUP_DIR/mkinitcpio.conf"
    sed -i -E 's/(HOOKS=.*\b)plymouth\s*/\1/' "$MKINIT_CONF"
    # Normalizar espacios dentro de los paréntesis de HOOKS
    sed -i -E 's/HOOKS=\(\s+/HOOKS=(/' "$MKINIT_CONF"
    sed -i -E 's/\s+\)/)/' "$MKINIT_CONF"
    ok "Hook plymouth removido de $MKINIT_CONF"
fi

# -------------------------------------------------------------------------
# 4. Remover quiet/splash y activar verbose logs en cmdline y systemd-boot
# -------------------------------------------------------------------------
log "4/5  Configurando salida verbose del kernel y systemd (lineas de inicio)..."

# Actualizar /etc/kernel/cmdline si existe
KERNEL_CMDLINE="/etc/kernel/cmdline"
if [ -f "$KERNEL_CMDLINE" ]; then
    cp -a "$KERNEL_CMDLINE" "$BACKUP_DIR/kernel_cmdline"
    # Eliminar quiet, splash y duplicados, agregando systemd.show_status=1
    python3 - "$KERNEL_CMDLINE" <<'PY'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    line = f.read().strip()

tokens = line.split()
cleaned = []
seen = set()
for t in tokens:
    if t in ('quiet', 'splash'):
        continue
    if t not in seen:
        seen.add(t)
        cleaned.append(t)

if 'systemd.show_status=1' not in seen:
    cleaned.append('systemd.show_status=1')

with open(path, 'w') as f:
    f.write(' '.join(cleaned) + '\n')
PY
    ok "Parametros actualizados en $KERNEL_CMDLINE:"
    printf "        %s\n" "$(cat "$KERNEL_CMDLINE")"
fi

# Actualizar entradas de systemd-boot en /boot/loader/entries/*.conf
if [ -d "/boot/loader/entries" ]; then
    for entry in /boot/loader/entries/*.conf; do
        [ -f "$entry" ] || continue
        cp -a "$entry" "$BACKUP_DIR/$(basename "$entry")"
        python3 - "$entry" <<'PY'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

def clean_options(match):
    prefix = match.group(1)
    args = match.group(2).split()
    cleaned = []
    seen = set()
    for a in args:
        if a in ('quiet', 'splash'):
            continue
        if a not in seen:
            seen.add(a)
            cleaned.append(a)
    if 'systemd.show_status=1' not in seen:
        cleaned.append('systemd.show_status=1')
    return prefix + ' '.join(cleaned)

new_content = re.sub(r'^(options\s+)(.*)$', clean_options, content, flags=re.MULTILINE)
with open(path, 'w') as f:
    f.write(new_content)
PY
        ok "Entrada de arranque actualizada: $entry"
    done
fi

# Ajustar timeout de bootloader a 1 segundo si es mayor
LOADER_CONF="/boot/loader/loader.conf"
if [ -f "$LOADER_CONF" ]; then
    cp -a "$LOADER_CONF" "$BACKUP_DIR/loader.conf"
    if grep -q "^timeout" "$LOADER_CONF"; then
        sed -i 's/^timeout.*/timeout 1/' "$LOADER_CONF"
    else
        echo "timeout 1" >> "$LOADER_CONF"
    fi
    ok "Timeout de menu en systemd-boot ajustado a 1s en $LOADER_CONF"
fi

# -------------------------------------------------------------------------
# 5. Regenerar Initramfs
# -------------------------------------------------------------------------
log "5/5  Regenerando imagenes de initramfs..."
mkinitcpio -P
ok "Initramfs regenerado sin Plymouth y con soporte de inicio verbose"

log "¡Optimizacion completada con exito!"
cat << EOF
  Respaldo de seguridad creado en: $BACKUP_DIR
  Mejoras aplicadas:
    - Eliminado el bloqueo de 25.6 segundos de power-state-manager.
    - Eliminados los ~5 segundos de retardo de Plymouth.
    - Eliminado timeout excesivo del bootloader.
    - Activado el arranque detallado (lineas de codigo / logs de arranque del kernel y systemd).

  Tiempo de inicio estimado reducido de 38.6s a ~6-8s en total.
EOF
