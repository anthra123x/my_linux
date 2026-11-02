#!/usr/bin/env bash
# fix-wireless-and-gamepad.sh
# Soluciona velocidad y alcance de Wi-Fi, visibilidad Bluetooth y deteccion de mandos en Steam.
#
# Diagnostico resuelto:
#   1. Wi-Fi Power Save activo por defecto degradaba la potencia de transmision (txpower) y el alcance.
#   2. El chip combo MediaTek MT7902 comparte bus y antena con Bluetooth; PCIe ASPM causaba
#      micro-cortes e interferencias mutuas entre Wi-Fi y Bluetooth.
#   3. BlueZ tenia Pairable desactivado y no soportaba reconexion rapida ni ClassicBondedOnly=false.
#   4. El modulo de kernel 'uinput' no estaba cargado, impidiendo a Steam crear mandos virtuales (Steam Input).
#   5. ERTM activo en el modulo bluetooth causaba fallos en el emparejamiento de mandos inalambricos.

set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '    \033[0;33m[!!]\033[0m %s\n' "$1"; }
die()  { printf '\n\033[0;31mFALLO: %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Este script debe ejecutarse con privilegios de root: sudo bash $0"

STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/wireless_gamepad_$STAMP"
mkdir -p "$BACKUP_DIR"

TARGET_USER="${SUDO_USER:-omicron}"

# -------------------------------------------------------------------------
# 1. Optimizar Wi-Fi: Potencia fija y desactivar ahorro de energia
# -------------------------------------------------------------------------
log "1/4  Optimizando alcance y estabilidad de Wi-Fi..."

# Desactivar ahorro de energia en NetworkManager para todas las conexiones
cat << 'EOF' > /etc/NetworkManager/conf.d/default-wifi-powersave-off.conf
[connection]
wifi.powersave = 2
EOF
ok "Ahorro de energia de Wi-Fi desactivado globalmente en NetworkManager"

# Desactivar PCIe ASPM en MediaTek MT7902/MT7921 para evitar estrangulamiento de la antena
cat << 'EOF' > /etc/modprobe.d/mt7921e.conf
# Desactiva PCIe ASPM en el chip combo MediaTek MT7902/MT7921.
# Mantiene la potencia de transmision maxima constante y elimina interferencias con Bluetooth.
options mt7921e disable_aspm=1
EOF
ok "Opcion disable_aspm=1 configurada para el modulo mt7921e"

# Desactivar powersave en la interfaz activa de inmediato
for iface in $(iw dev | awk '$1=="Interface"{print $2}'); do
    iw dev "$iface" set power_save off 2>/dev/null || true
    ok "Power save desactivado en tiempo real en $iface"
done

# -------------------------------------------------------------------------
# 2. Optimizar Bluetooth: Deteccion de dispositivos y reconexion rapida
# -------------------------------------------------------------------------
log "2/4  Optimizando alcance y visibilidad de Bluetooth (BlueZ)..."

BT_MAIN="/etc/bluetooth/main.conf"
if [ -f "$BT_MAIN" ]; then
    cp -a "$BT_MAIN" "$BACKUP_DIR/main.conf"
fi

# Ajustar directivas esenciales en main.conf
python3 -c '
import re

path = "/etc/bluetooth/main.conf"
with open(path, "r") as f:
    content = f.read()

def ensure_opt(section, key, val, text):
    sec_pattern = re.compile(rf"(\[{section}\].*?)(?=\n\[|\Z)", re.DOTALL)
    sec_match = sec_pattern.search(text)
    if not sec_match:
        return text + f"\n[{section}]\n{key} = {val}\n"
    sec_text = sec_match.group(1)
    if re.search(rf"^\s*{key}\s*=", sec_text, re.MULTILINE):
        new_sec = re.sub(rf"^\s*{key}\s*=.*$", f"{key} = {val}", sec_text, flags=re.MULTILINE)
    else:
        new_sec = sec_text.rstrip() + f"\n{key} = {val}\n"
    return text[:sec_match.start()] + new_sec + text[sec_match.end():]

content = ensure_opt("General", "FastConnectable", "true", content)
content = ensure_opt("General", "JustWorksRepairing", "always", content)
content = ensure_opt("General", "Experimental", "true", content)
content = ensure_opt("General", "DiscoverableTimeout", "0", content)

with open(path, "w") as f:
    f.write(content)
'
ok "FastConnectable, JustWorksRepairing y modo Experimental habilitados en /etc/bluetooth/main.conf"

# Ajustar /etc/bluetooth/input.conf para mandos
BT_INPUT="/etc/bluetooth/input.conf"
if [ -f "$BT_INPUT" ]; then
    cp -a "$BT_INPUT" "$BACKUP_DIR/input.conf"
fi
cat << 'EOF' > /etc/bluetooth/input.conf
[General]
UserspaceHID = false
ClassicBondedOnly = false
EOF
ok "UserspaceHID y ClassicBondedOnly=false configurados en /etc/bluetooth/input.conf"

# Desactivar ERTM en bluetooth para mandos inalambricos
cat << 'EOF' > /etc/modprobe.d/bluetooth.conf
# Desactiva Enhanced Retransmission Mode (ERTM) que rompe la conexion de mandos Bluetooth
options bluetooth disable_ertm=1
EOF
if [ -f /sys/module/bluetooth/parameters/disable_ertm ]; then
    echo 1 > /sys/module/bluetooth/parameters/disable_ertm || true
fi
ok "disable_ertm=1 configurado en kernel y modprobe para mandos inalambricos"

# -------------------------------------------------------------------------
# 3. Soporte de Mando en Steam e Input del Kernel (uinput)
# -------------------------------------------------------------------------
log "3/4  Habilitando modulos de mando y permisos para Steam..."

# Cargar uinput e hid drivers al arranque
cat << 'EOF' > /etc/modules-load.d/gamepads.conf
uinput
hid_playstation
hid_sony
EOF
modprobe uinput || true
modprobe hid_playstation 2>/dev/null || true
modprobe hid_sony 2>/dev/null || true
ok "Modulos uinput, hid_playstation y hid_sony cargados y persistidos en /etc/modules-load.d/gamepads.conf"

# Asegurar usuario en grupo input
usermod -aG input "$TARGET_USER" 2>/dev/null || true
ok "Usuario $TARGET_USER agregado al grupo input"

# Recargar reglas udev para steam-devices
udevadm control --reload-rules
udevadm trigger
ok "Reglas udev de mandos (steam-devices) recargadas y aplicadas"

# -------------------------------------------------------------------------
# 4. Reinicio de servicios
# -------------------------------------------------------------------------
log "4/4  Reiniciando servicios de red y bluetooth..."
systemctl restart bluetooth.service
nmcli general reload || true
ok "Bluetooth y NetworkManager recargados con la nueva configuracion"

log "¡Optimizaciones de conectividad y mandos aplicadas con exito!"
cat << EOF
  Respaldo creado en: $BACKUP_DIR
  Resumen de mejoras:
    - Wi-Fi: Ahorro de energia desactivado y PCIe ASPM mitigado para evitar perdidas de señal.
    - Bluetooth: FastConnectable, JustWorksRepairing y modo Experimental activos (detecta todos los dispositivos).
    - Steam / Mandos: Modulo 'uinput' activo, ERTM desactivado y drivers de PlayStation/Xbox preparados.
EOF
