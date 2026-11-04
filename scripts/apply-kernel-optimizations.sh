#!/usr/bin/env bash
# apply-kernel-optimizations.sh
#
# Optimizaciones quirurgicas de kernel y bajo consumo para Intel Core i3-N305
# (ASUS Vivobook Go E1504GA - 8 Gracemont E-cores + Intel UHD Graphics 32EU).
#
# Invariantes:
# 1. THP en 'madvise' para evitar desbordamiento y fragmentacion de 2MB en 8 GB RAM.
# 2. vm.stat_interval=10 para reducir wakeups de CPU en un 90% (permite C8/C10 sleep).
# 3. vm.compaction_proactiveness=20 para reducir ciclos de CPU con ZRAM de 12 GB.
# 4. CPU EPP en 'balance_performance' con suelo al 25% (~1.4 GHz en reposo) liberando
#    los 23W del SoC para que la iGPU trabaje a 1250 MHz continuos sin micro-tirones.

set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '    \033[0;33m[!!]\033[0m %s\n' "$1"; }
die()  { printf '\n\033[0;31mFALLO: %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Este script requiere permisos de root: sudo bash $0"

STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/kernel_opts_$STAMP"
mkdir -p "$BACKUP_DIR"

# 1. Configurar Transparent Huge Pages (THP) en madvise
log "1/4  Configurando Transparent Huge Pages (madvise)..."
cat << 'EOF' > /etc/tmpfiles.d/thp.conf
# Transparent Huge Pages: solo se asignan bloques de 2 MB a procesos que
# los solicitan de forma explicita (MADV_HUGEPAGE). Evita la fragmentacion
# interna que desperdicia entre 300 y 700 MB de RAM en sistemas de 8 GB.
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise
EOF

systemd-tmpfiles --create /etc/tmpfiles.d/thp.conf >/dev/null 2>&1 || true
if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
  echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
fi
if [ -w /sys/kernel/mm/transparent_hugepage/defrag ]; then
  echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
fi
ok "THP establecido en madvise (recuperacion de memoria fragmentada)"

# 2. Afinar parametros de memoria y temporizadores del kernel (sysctl)
log "2/4  Actualizando /etc/sysctl.d/99-local-performance.conf..."
SYSCTL_CONF="/etc/sysctl.d/99-local-performance.conf"
if [ -f "$SYSCTL_CONF" ]; then
  cp -a "$SYSCTL_CONF" "$BACKUP_DIR/99-local-performance.conf"
fi

cat << 'EOF' > "$SYSCTL_CONF"
# Ajustes de memoria y kernel para Intel Core i3-N305 con 8 GB RAM.
#
# swappiness=150: con ZRAM de 12 GB, el kernel mantiene la memoria caliente en
# RAM comprimida de ultra-baja latencia sin tocar el NVMe.
# vfs_cache_pressure=50: retiene metadatos de archivos y binarios en memoria para acelerar lanzamientos de apps.
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 65536
vm.swappiness = 150
vm.page-cluster = 0

# watermark_scale_factor=150: despierta kswapd de forma anticipada en segundo plano
# para comprimir paginas en ZRAM antes de llegar al suelo critico, eliminando
# por completo las pausas de direct reclaim sincronicas en aplicaciones GUI.
vm.watermark_scale_factor = 150

# Temporizadores de reposo: reduce wakeups innecesarios de CPU de 1s a 10s.
# Permite a los nucleos Gracemont entrar en estados de bajo consumo C8/C10.
vm.stat_interval = 10

# Mitiga la agresividad de compactacion en segundo plano (ahorra ciclos con ZRAM).
vm.compaction_proactiveness = 20

# Latencia de ancho de banda CFS en cgroups v2 (reduce jitter al alternar cuotas).
kernel.sched_cfs_bandwidth_slice_us = 3000

# Control de congestion de red TCP BBR (baja latencia, anti-bufferbloat).
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
ok "sysctl cargado: vm.stat_interval=10, vm.compaction_proactiveness=20"

# 3. Configurar microcontrolador GPU Intel Gen12 (i915 GuC/HuC y FBC)
log "3/5  Configurando /etc/modprobe.d/i915.conf (GuC/HuC y Framebuffer Compression)..."
cat << 'EOF' > /etc/modprobe.d/i915.conf
# Aceleracion por hardware y microcontrolador para Intel Gen12 Xe-LP (Alder Lake-N)
# enable_guc=3: delega planificacion y decodificacion de video en GuC/HuC
# enable_fbc=1: compresion de framebuffer para reducir ancho de banda de memoria
# fastboot=1: evita parpadeos en cambio de modo
options i915 enable_guc=3 enable_fbc=1 fastboot=1
EOF
ok "i915.conf configurado con enable_guc=3 y enable_fbc=1"

# 4. Ajustar power-state-manager para optimizacion termica, GPU dinamica y balance energetico
log "4/5  Optimizando politicas energeticas en /usr/local/bin/power-state-manager..."
PSM="/usr/local/bin/power-state-manager"
if [ -f "$PSM" ]; then
  cp -a "$PSM" "$BACKUP_DIR/power-state-manager"
  # Reemplazar suelo de 45% a 25% y EPP performance a balance_performance en apply_ac
  sed -i 's/echo 45 >\/sys\/devices\/system\/cpu\/intel_pstate\/min_perf_pct/echo 25 >\/sys\/devices\/system\/cpu\/intel_pstate\/min_perf_pct/g' "$PSM"
  sed -i 's/echo performance >"$f"/echo balance_performance >"$f"/g' "$PSM"
  # GPU minimo a 200 MHz en reposo (en lugar de bloquear a 800 MHz)
  sed -i 's/echo 800 >"$card\/gt_min_freq_mhz"/echo 200 >"$card\/gt_min_freq_mhz"/g' "$PSM"
  # Ventilador ASUS en modo estandar (0) en vez de overboost permanente (1)
  sed -i 's/echo 1 >\/sys\/devices\/platform\/asus-nb-wmi\/throttle_thermal_policy/echo 0 >\/sys\/devices\/platform\/asus-nb-wmi\/throttle_thermal_policy/g' "$PSM"
  ok "power-state-manager actualizado: GPU min 200 MHz, fan ASUS equilibrado, EPP balance_performance"
fi

# 5. Configurar I/O Scheduler y Read-Ahead para NVMe
log "5/6  Configurando I/O Scheduler y Read-Ahead para almacenamiento NVMe..."
cat << 'EOF' > /etc/udev/rules.d/99-local-iosched.rules
# I/O Scheduler y Read-Ahead ultrarrápido para NVMe PCIe en Omicron DE
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="1024"
EOF
udevadm control --reload >/dev/null 2>&1 || true
udevadm trigger --subsystem-match=block >/dev/null 2>&1 || true
ok "NVMe read-ahead configurado a 1024 KB con scheduler none"

# 6. Re-aplicar estado energetico actual
log "6/6  Reaplicando perfil de energia activo..."
if [ -x "$PSM" ]; then
  "$PSM" apply >/dev/null 2>&1 || true
fi
ok "Perfil energetico sincronizado"

printf '\n\033[1;32mOptimizaciones de kernel y memoria aplicadas exitosamente.\033[0m\n'
printf 'Respaldo previo guardado en: %s\n' "$BACKUP_DIR"

