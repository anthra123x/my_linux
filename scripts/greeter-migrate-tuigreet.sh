#!/usr/bin/env bash
# Reemplaza el greeter de Noctalia por tuigreet y borra Noctalia.
#
# POR QUE HAY QUE HACERLO EN ESTE ORDEN
# greetd tiene pointed a /usr/bin/noctalia-greeter-session como sesion de
# login. Si borras el paquete sin cambiar antes esa linea, greetd no encuentra
# la sesion que ejecutar, la pantalla de login no arranca y no podes loguearte.
# Con un Live USB se recupera, pero es un mal momento.
#
# El script verifica cada paso y vuelve a atrás solo si algo falla.
# Ejecutalo con:  sudo bash ~/.local/bin/greeter-migrate-tuigreet.sh
#
# Que hace, en orden:
#   1. Respalda /etc/greetd/config.toml
#   2. Instala greetd-tuigreet
#   3. Verifica que el binario de la sesion exista
#   4. Reescribe greetd apuntando a tuigreet, conservando el autologin
#   5. Verifica que la config sea TOML valido y que apunte a algo real
#   6. recien ahi borra noctalia-greeter
#   7. Limpia los rastros que el paquete dejo
#
# Para volver atras:  sudo cp /var/lib/greetd-backup/config.toml.TIMESTAMP /etc/greetd/config.toml

set -euo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/lib/greetd-backup
GREETD_CONF=/etc/greetd/config.toml
TUIGREET_SESSION=/usr/bin/tuigreet-session
OLD_SESSION=/usr/bin/noctalia-greeter-session

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32mOK\033[0m  %s\n' "$1"; }
warn() { printf '    \033[0;33m!!\033[0m  %s\n' "$1"; }
die()  { printf '\n\033[0;31mFALLO: %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "esto necesita root: sudo bash $0"

# ---------------------------------------------------------------- 1. respaldo
log "1/7  Respaldo de la config de greetd"
mkdir -p "$BACKUP_DIR"
cp -a "$GREETD_CONF" "$BACKUP_DIR/config.toml.$STAMP"
ok "respaldo en $BACKUP_DIR/config.toml.$STAMP"
ok "autologin actual:"
grep -A2 'initial_session' "$GREETD_CONF" | sed 's/^/        /'

rollback() {
    warn "algo fallo: restaurando la config original de greetd"
    cp -a "$BACKUP_DIR/config.toml.$STAMP" "$GREETD_CONF"
    ok "greetd restaurado a Noctalia. No se borro ningun paquete."
    systemctl restart greetd 2>/dev/null || true
    exit 1
}

# ------------------------------------------------------------------ 2. tuigreet
log "2/7  Instalacion de greetd-tuigreet"
if pacman -Qq greetd-tuigreet >/dev/null 2>&1; then
    ok "greetd-tuigreet ya estaba instalado"
else
    pacman -S --needed --noconfirm greetd-tuigreet || die "no se pudo instalar greetd-tuigreet"
    ok "greetd-tuigreet instalado"
fi

# ------------------------------------------------------------ 3. verificar binario
log "3/7  Verificacion del binario de sesion"
[ -x "$TUIGREET_SESSION" ] || {
    warn "no esta $TUIGREET_SESSION"
    warn "paquete: $(pacman -Ql greetd-tuigreet 2>/dev/null | grep -i session | tr '\n' ' ')"
    rollback
}
ok "$TUIGREET_SESSION existe y es ejecutable"

# ------------------------------------------------------- 4. reescribir greetd
log "4/7  Apuntando greetd a tuigreet"
# Se conservan [terminal] y [initial_session] tal cual: el autologin es lo que
# hace que la maquina entre sola, y es lo que te salva si el greeter falla.
#
# Ademas se saca "user = greeter" de [default_session]. Ese usuario (uid 961,
# home /var/lib/noctalia-greeter) lo creo el instalador de Noctalia, no el
# paquete, asi que pacman -Rns no lo borra. tuigreet no lo necesita: sin campo
# user, greetd corre la sesion con su propio usuario greetd.
python3 - "$GREETD_CONF" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'(?m)^command\s*=\s*".*"\s*$',
           'command = "/usr/bin/tuigreet-session"', s, count=1)
# solo el user de [default_session]: el de [initial_session] es el tuyo y se queda
s = re.sub(r'(?ms)(\[default_session\][^\[]*?)\n\s*user\s*=\s*"greeter"',
           r'\1', s, count=1)
open(p, "w").write(s)
PY
ok "sesion de login -> $TUIGREET_SESSION"
ok "user 'greeter' (creado por Noctalia) fuera de la config"

# -------------------------------------------------------- 5. validar la config
log "5/7  Validacion de la config resultante"
python3 - "$GREETD_CONF" <<'PY' || exit 1
import sys, tomllib, os
p = sys.argv[1]
try:
    with open(p, "rb") as f:
        cfg = tomllib.load(f)
except tomllib.TOMLDecodeError as e:
    print(f"    !! TOML invalido: {e}")
    sys.exit(1)

ds = cfg.get("default_session", {})
cmd = ds.get("command", "")
print(f"    -> default_session.command = {cmd}")

if not os.path.isfile(cmd) or not os.access(cmd, os.X_OK):
    print(f"    !! la sesion de login no existe o no es ejecutable: {cmd}")
    sys.exit(1)

ini = cfg.get("initial_session")
if ini:
    print(f"    -> initial_session.command = {ini.get('command')}")
    print("    -> autologin conservado: si el greeter falla, la sesion entra igual")
else:
    print("    -> no hay initial_session (queda solo el login manual)")
PY
[ $? -eq 0 ] || rollback
ok "config valida y apuntando a un binario real"

# ----------------------------------------------------------- 6. borrar noctalia
log "6/7  Borrado de noctalia-greeter"
if [ ! -e "$OLD_SESSION" ]; then
    ok "noctalia-greeter ya no esta instalado"
else
    pacman -Rns --noconfirm noctalia-greeter || die "pacman no pudo borrar noctalia-greeter"
    [ -e "$OLD_SESSION" ] && die "el binario sigue existiendo, no continúo"
    ok "noctalia-greeter desinstalado"
fi

# ------------------------------------------------------------ 7. limpiar rastros
log "7/7  Limpieza de rastros de Noctalia"
# La polkit action la deja el paquete; pacman -Rns deberia llevarsela, pero
# si el archivo quedo con otro dueño se queda colgando.
rm -f /usr/share/polkit-1/actions/org.noctalia.greeter.apply-appearance.policy
ok "polkit action borrada"

rm -f /usr/lib/tmpfiles.d/noctalia-greeter.conf
ok "tmpfiles borrado"

# El usuario greeter lo creo el instalador de Noctalia, no el paquete, asi que
# pacman -Rns no lo toca. Su home es /var/lib/noctalia-greeter, que ya no lo
# necesita nadie. Se borra recien ahora, cuando la config ya no lo referencia.
if getent passwd greeter >/dev/null 2>&1; then
    if getent passwd greeter | grep -q '/var/lib/noctalia-greeter'; then
        userdel -r greeter 2>/dev/null \
            && ok "usuario 'greeter' borrado (era de Noctalia)" \
            || warn "no se pudo borrar el usuario 'greeter' (no es critico)"
    else
        warn "el usuario 'greeter' existe pero su home no es de Noctalia: no lo toco"
    fi
fi

if [ -d /var/lib/noctalia-greeter ]; then
    rm -rf /var/lib/noctalia-greeter
    ok "/var/lib/noctalia-greeter borrado"
fi

systemctl restart greetd 2>/dev/null && ok "greetd reiniciado" || warn "greetd no se reinicio (normal si no estabas en VT1)"

# ------------------------------------------------------------------- resumen
log "Residual: verificacion final"
LEFT=$(pacman -Qq 2>/dev/null | grep -i noctalia || true)
[ -z "$LEFT" ] && ok "ningun paquete noctalia instalado" || warn "quedan: $LEFT"

LEFT2=$(grep -rl 'noctalia' /etc/greetd/ /usr/bin/ 2>/dev/null | grep -v 'greetd-backup' || true)
[ -z "$LEFT2" ] && ok "ninguna referencia a noctalia en greetd ni /usr/bin" || warn "referencias: $LEFT2"

log "Listo"
cat <<EOF
  Greeter:   tuigreet  (puedes cambiarlo por gtkgreet o sddm cuando quieras)
  Autologin: conservado en [initial_session]
  Respaldo:  $BACKUP_DIR/config.toml.$STAMP
  Volver:    sudo cp $BACKUP_DIR/config.toml.$STAMP /etc/greetd/config.toml

  Probalo SIN reiniciar: sali de la sesion y volve a entrar. Si la pantalla
  de login se ve rara, el autologin te entra igual y desde ahi:
      sudo cp $BACKUP_DIR/config.toml.$STAMP /etc/greetd/config.toml
EOF
