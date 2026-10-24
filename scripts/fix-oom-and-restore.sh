#!/usr/bin/env bash
# Repara la causa raiz de las perdidas de sesion, y lo que rompi antes.
#
# ============================================================================
# EL DIAGNOSTICO
# ============================================================================
# No era un reinicio: tu sesion moria. La cadena era esta:
#
#   1. Se acaba la memoria (RAM + zram)
#   2. El OOM killer del kernel mata el proceso mas gordo
#   3. systemd ve que un OOM-kill ocurrio DENTRO del cgroup de
#      wayland-wm@hyprland.desktop.service, lo marca como fallido y dispara
#      sus OnFailure=: se desmonta la sesion entera
#   4. Hyprland segfaultea en libaquamarine mientras lo desmontan
#   5. greetd te muestra el greeter y perdes todo
#
# Ya se corrigio el paso 3 (OOMPolicy=continue en wayland-wm@.service, que es
# un drop-in de usuario y no necesita root). Con eso, si matan a una app, la
# app muere y la sesion sigue.
#
# Falta corregir el paso 1, que es la causa de fondo:
#
#   RAM:  7,4 GiB
#   zram: 7,4 GB de disksize   <-- zram es RAM, no disco
#   swap en disco: 0            <-- no hay donde caer
#   swappiness: 150             <-- manda todo a zram
#
# zram con disksize = 100% de la RAM es una trampa: cuando el kernel mete
# paginas en zram, esa memoria sigue siendo RAM. Si zram se llena, se acabo la
# RAM fisica y no hay red de seguridad. Resultado: OOM global.
#
# ============================================================================
# QUE HACE ESTE SCRIPT
# ============================================================================
#   1. Crea un swapfile de 8 GB en la NVMe  -> la red de seguridad que falta
#   2. Limita zram a 3 GB                     -> deja de ser una bomba de RAM
#   3. Deja swappiness en 150                 -> correcto con zram, ahora seguro
#      (con zram delante del disco, lo caliente se queda comprimido en RAM y
#       lo frio baja al swapfile; eso es lo que hace rapido un equipo de 8 GB)
#   4. Repara los 2 paquetes que borre de mas
#   5. Cambia el greeter de Noctalia a tuigreet
#
# Ejecutalo con:  sudo bash ~/.local/bin/fix-oom-and-restore.sh
#
# Para deshacer la parte del swapfile:
#   sudo swapoff /swapfile && sudo rm /swapfile

set -euo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
SWAPFILE=/swapfile
SWAP_SIZE_MB=8192
ZRAM_SIZE_MB=3072
BACKUP_DIR=/var/lib/local-perf-backup

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32mOK\033[0m  %s\n' "$1"; }
warn() { printf '    \033[0;33m!!\033[0m  %s\n' "$1"; }
die()  { printf '\n\033[0;31mFALLO: %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "necesita root: sudo bash $0"

MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
log "Equipo: $((MEM_KB/1024/1024)) GB de RAM, $(df -h --output=avail / | tail -1 | tr -d ' ') libres en disco"

# =============================================================== 1. swapfile
log "1/5  Swapfile en disco (la red de seguridad que no tenias)"

if swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
    ok "$SWAPFILE ya esta activo, no se toca"
elif [ -e "$SWAPFILE" ]; then
    warn "$SWAPFILE existe pero no esta activo; lo reviso"
    file "$SWAPFILE" | grep -q 'sparse file' || die "$SWAPFILE existe y no es un swapfile. Revisalo a mano."
else
    # En btrfs un swapfile necesita NOCOW: sin esto el kernel lo rechaza con
    # "swapon failed: Invalid argument".
    FSTYPE=$(findmnt -no FSTYPE /)
    ok "filesystem de la raiz: $FSTYPE"

    if [ "$FSTYPE" = "btrfs" ]; then
        log "    creando $SWAP_SIZE_MB MB en btrfs (con NOCOW)"
        # Con NOCOW: el swap es escribible sin copiar al journal.
        fallocate -l "${SWAP_SIZE_MB}M" "$SWAPFILE" 2>/dev/null \
            || dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB" status=progress
        chattr +C "$SWAPFILE"
        ok "chattr +C aplicado (obligatorio en btrfs)"
    else
        fallocate -l "${SWAP_SIZE_MB}M" "$SWAPFILE"
    fi

    chmod 600 "$SWAPFILE"
    ok "archivo creado ($(du -h "$SWAPFILE" | cut -f1))"

    mkswap "$SWAPFILE" >/dev/null
    ok "mkswap hecho"

    # Prioridad 10: mas baja que zram (100). Asi el kernel usa zram primero
    # (que es RAM comprimida, rapidisimo) y cae al disco solo lo que no entra.
    swapon -p 10 "$SWAPFILE"
    ok "swapfile activo con prioridad 10 (zram tiene 100)"
fi

# Persistirlo en el arranque
if ! grep -q "^$SWAPFILE " /etc/fstab 2>/dev/null; then
    printf '%s none swap sw,pri=10 0 0\n' "$SWAPFILE" >> /etc/fstab
    ok "anadido a /etc/fstab (arranca solo)"
else
    ok "ya estaba en /etc/fstab"
fi

# =============================================================== 2. zram
log "2/5  Limitando zram (de 7,4 GB a $ZRAM_SIZE_MB MB)"

mkdir -p /etc/systemd/zram-generator
ZRAM_CONF=/etc/systemd/zram-generator/zram-generator.conf
[ -f "$ZRAM_CONF" ] && cp -a "$ZRAM_CONF" "$BACKUP_DIR/zram-generator.conf.$STAMP" 2>/dev/null || true

cat > "$ZRAM_CONF" <<EOF
# Configuracion de zram.
#
# zram es RAM comprimida, no disco. Con disksize = 7,4 GB en un equipo de
# 7,4 GB de RAM, el kernel podia llenarlo entero y quedarse sin RAM fisica:
# ahi el OOM killer mataba procesos y la sesion se caia.
#
# Ahora zram es lo que debe ser: una cache caliente de 3 GB, comprimida, con
# el swapfile de 8 GB como respaldo para lo que no entra. El resultado es que
# el equipo responde igual de rapido y ya no hay spiral de OOM.
[ZRAM]
zram-size = $ZRAM_SIZE_MB MiB
compression-algorithm = zstd
swap-priority = 100
EOF
ok "escrito $ZRAM_CONF (backup en $BACKUP_DIR si existia)"

# Efecto inmediato: reducir el zram que ya esta montado.
CURRENT_MB=$(( $(cat /sys/block/zram0/disksize 2>/dev/null || echo 0) / 1024 / 1024 ))
if [ "$CURRENT_MB" -gt "$ZRAM_SIZE_MB" ]; then
    warn "zram actual: ${CURRENT_MB} MB -> solo bajara a $ZRAM_SIZE_MB MB en el proximo reinicio"
    warn "para bajarlo ya habria que reiniciar o recrear el dispositivo a mano"
    warn "no lo hago solo: un reinicio te cortaria la sesion de OpenCode"
else
    ok "zram ya esta en ${CURRENT_MB} MB"
fi

# =============================================================== 3. sysctl
log "3/5  Ajustando sysctl"

SYSCTL=/etc/sysctl.d/99-local-performance.conf
mkdir -p "$BACKUP_DIR"
[ -f "$SYSCTL" ] && cp -a "$SYSCTL" "$BACKUP_DIR/99-local-performance.conf.$STAMP" && ok "respaldo del sysctl anterior en $BACKUP_DIR"

cat > "$SYSCTL" <<'EOF'
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
vm.vfs_cache_pressure = 25
vm.min_free_kbytes = 65536
vm.swappiness = 150
vm.page-cluster = 0
EOF
sysctl --system >/dev/null 2>&1
ok "sysctl aplicado:"
for k in vm.vfs_cache_pressure vm.min_free_kbytes vm.swappiness vm.page-cluster; do
    printf '        %-24s %s\n' "$k" "$(sysctl -n "$k")"
done

# =============================================================== 4. paquetes
log "4/5  Reparando los 2 paquetes que borre de mas"

# ghostty: es la terminal, y su proceso actual corre sobre un binario borrado
# (el inode vive en memoria pero el archivo no). Sin esto no se puede relanzar.
if pacman -Qq ghostty >/dev/null 2>&1; then
    ok "ghostty ya instalado"
else
    pacman -S --needed --noconfirm ghostty && ok "ghostty reinstalado" || warn "no se pudo instalar ghostty"
fi

# hyprpolkitagent: sin el, no hay agente de permisos. Cualquier accion de admin
# (instalar paquetes, cambiar energia) se queda esperando una contrasena que no
# aparece. Ademas ya segfaulteo una vez con el binario borrado.
if pacman -Qq hyprpolkitagent >/dev/null 2>&1; then
    ok "hyprpolkitagent ya instalado"
else
    pacman -S --needed --noconfirm hyprpolkitagent && ok "hyprpolkitagent reinstalado" || warn "no se pudo instalar hyprpolkitagent"
fi

# ================================================================= 5. greeter
log "5/5  Cambiando el greeter de Noctalia a tuigreet"
if pacman -Qq noctalia-greeter >/dev/null 2>&1; then
    bash /home/omicron/.local/bin/greeter-migrate-tuigreet.sh
else
    ok "noctalia-greeter ya no esta instalado"
fi

# =================================================================== resumen
log "Estado final de la memoria"
free -h | sed 's/^/    /'
echo
swapon --show | sed 's/^/    /'
echo
log "Listo"
cat <<EOF
  Lo que ya quedo arreglado (sin root, desde la sesion anterior):
    - wayland-wm@hyprland.desktop.service con OOMPolicy=continue
      -> si el OOM killer mata una app, la sesion NO se cae
    - OOMScoreAdjust=-900 en el compositor
      -> Hyprland deja de ser candidato del OOM killer
    - restore de sesion: si aun asi se cae, te vuelve a abrir las apps

  Lo que si o si necesita un reinicio para terminar de aplicarse:
    - zram baja de 7,4 GB a 3 GB
    - swappiness y min_free_kbytes nuevos

  Que hacer ahora:
    1. Guarda lo que tengas abierto.
    2. Reinicia.  (Ahi es cuando zram se ajusta de verdad.)
    3. Comprobá con free -h y swapon --show que hay 8 GB de swap mas zram.

  Si algo quedo mal, el respaldo del sysctl esta en:
    $BACKUP_DIR/99-local-performance.conf.$STAMP
EOF
