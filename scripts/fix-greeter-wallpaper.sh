#!/usr/bin/env bash
# Poner wallpaper en la pantalla de inicio de sesion (noctalia-greeter).
#
# ============================================================================
# POR QUE NO SE VE
# ============================================================================
# Dos motivos, ambos reales:
#
# 1) PERMISOS. Tu home es /home/omicron con permisos 700 (drwx------).
#    El greeter corre como el usuario "greeter", asi que no puede ni siquiera
#    ENTRAR a /home/omicron, y por lo tanto no puede leer ningun wallpaper que
#    tengas ahi. No es que la ruta este mal: es que no tiene permiso de
#    atravesar el directorio.
#
#    La solucion NO es abrir tu home a todo el mundo. Es copiar el wallpaper a
#    una ruta que si sea legible por todos: /usr/share/backgrounds/.
#
# 2) CONFIGURACION. El greeter lee /var/lib/noctalia-greeter/greeter.toml, que
#    tiene una seccion [appearance.wallpaper] con la ruta. Ese archivo es del
#    usuario "greeter" (permisos 750), asi que este script necesita root.
#
# ============================================================================
# QUE HACE
# ============================================================================
#   1. Copia el wallpaper a /usr/share/backgrounds/ (legible por todos)
#   2. Respalda greeter.toml
#   3. Inyecta [appearance.wallpaper] apuntando a la copia, y quita los
#      overrides por pantalla, que tienen prioridad sobre el global
#      (si un override existe, ignora el wallpaper global)
#   4. Aplica con noctalia-greeter-apply-appearance y verifica
#   5. Activa el sync automatico para que el wallpaper no se vuelva a romper
#
# Ejecutalo con:  sudo bash ~/.local/bin/fix-greeter-wallpaper.sh
#
# Para deshacer:  sudo cp <el .bak que imprime> /var/lib/noctalia-greeter/greeter.toml

set -euo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
SRC="${1:-/home/omicron/Imágenes/wallpapers/wallhaven-xek51o.png}"
DEST_DIR=/usr/share/backgrounds
DEST="$DEST_DIR/login-wallpaper.png"
STATE=/var/lib/noctalia-greeter
TOML="$STATE/greeter.toml"
STAGING=/tmp/noctalia-greeter-staging

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32mOK\033[0m  %s\n' "$1"; }
warn() { printf '    \033[0;33m!!\033[0m  %s\n' "$1"; }
die()  { printf '\n\033[0;31mFALLO: %s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "necesita root: sudo bash $0 [ruta-del-wallpaper]"

# ------------------------------------------------- 0. comprobar la imagen
log "0/5  Comprobando la imagen de origen"
[ -f "$SRC" ] || die "no existe el archivo: $SRC
Pasa la ruta como argumento:
  sudo bash ~/.local/bin/fix-greeter-wallpaper.sh /ruta/a/tu/wallpaper.png"

python3 - "$SRC" <<'PY' || die "el archivo no es una imagen valida"
import struct, sys
d = open(sys.argv[1], "rb").read(33)
if d[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit(1)
w, h = struct.unpack(">II", d[16:24])
print(f"    PNG {w}x{h}")
PY
ok "imagen valida: $SRC"

# ------------------------------------------------- 1. copia legible
log "1/5  Copiando a una ruta legible por el usuario 'greeter'"
mkdir -p "$DEST_DIR"
install -m 0644 -o root -g root "$SRC" "$DEST"
ok "instalado en $DEST (0644 root:root)"
ok "cualquier usuario, incluido 'greeter', ya puede leerlo"

# Verificacion real de permisos, no de teoria
if sudo -u greeter test -r "$DEST" 2>/dev/null; then
    ok "verificado: el usuario 'greeter' SI puede leerlo"
else
    warn "el usuario 'greeter' todavia no puede leerlo (revisar el home)"
fi

# ------------------------------------------------- 2. respaldo
log "2/5  Respaldando la configuracion actual del greeter"
mkdir -p "$STATE"
BACKUP="$STATE/greeter.toml.bak-$STAMP"
if [ -f "$TOML" ]; then
    cp -a "$TOML" "$BACKUP"
    ok "respaldo en $BACKUP"
else
    ok "no habia greeter.toml todavia, se creara desde cero"
    : > "$BACKUP"
fi

# ------------------------------------------------- 3. inyectar la seccion
log "3/5  Configurando [appearance.wallpaper]"

# Se parte del TOML existente y se le cambia SOLO la seccion del wallpaper.
# Esto preserva la paleta, el tema y el resto de la apariencia, en vez de
# pisar el archivo entero con un config inventado.
rm -rf "$STAGING"
mkdir -p "$STAGING"

python3 - "$BACKUP" "$STAGING/greeter.toml" "$DEST" <<'PY'
import re, sys

src, dst, wallpaper = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()

# Los overrides por pantalla [appearance.wallpapers.<conector>] tienen
# prioridad sobre el wallpaper global. Si queda alguno, el global se ignora
# y por eso se quitan.
removed = 0
out, skip = [], False
for line in text.splitlines():
    if re.match(r"^\s*\[appearance\.wallpapers\.[^\]]+\]", line):
        skip = True
        removed += 1
        continue
    if skip:
        # se sale del bloque en la siguiente linea de seccion de nivel superior
        if re.match(r"^\s*\[(?!appearance\.wallpapers\.)", line):
            skip = False
        else:
            continue
    out.append(line)
text = "\n".join(out)

# --- Ajustes de estilo Windows 11 ---------------------------------------
#
# Solo se tocan claves cuyo esquema esta CONFIRMADO en el binario del
# greeter, no inventado. El propio binario declara:
#
#   # [appearance] scheme, password_style, hide_logo, power_buttons_position,
#   #   scheme_selector_position, theme_mode, corner_radius_scale, font_family
#
# De esa lista solo se usan hide_logo y power_buttons_position:
#   - hide_logo es un booleano, no hay ambiguedad. Win11 no muestra un logo
#     grande en la tarjeta de inicio de sesion.
#   - power_buttons_position acepta "bottom-right", que es donde Win11
#     pone el boton de apagado.
#
# NO se tocan theme_mode, scheme, password_style ni corner_radius_scale porque
# el binario no expone sus valores validos (searching for them devuelve solo
# el mensaje "invalid appearance.X value" sin la lista). Adivinarlos podria
# hacer que el greeter rechace el archivo entero. Esos se cambian desde el
# propio panel de apariencia del greeter, que ademas permite ver el resultado.

def set_scalar(text, key, raw_value):
    """Pone clave = valor dentro de [appearance], creandola si no existe.
    No toca la seccion [appearance.wallpaper], que se maneja aparte.
    Devuelve el texto modificado."""
    pat = re.compile(rf"(?m)^(\s*){re.escape(key)}\s*=.*$")
    if pat.search(text):
        antes = pat.search(text).group(0).strip()
        nuevo = pat.sub(rf"\g<1>{key} = {raw_value}", text, count=1)
        if antes != f"{key} = {raw_value}":
            print(f"    {key}: {antes}  ->  {key} = {raw_value}")
        else:
            print(f"    {key}: ya estaba en {raw_value}")
        return nuevo
    # Se inserta justo despues de la linea de encabezado [appearance].
    # Insertar al final del bloque es mas frágil: m.end() cae pegado al
    # comienzo de la siguiente seccion y la clave nueva queda pegada a ella,
    # lo que produce un TOML invalido ("clave = valor[otra.seccion]").
    ap = re.compile(r"(?m)^\[appearance\][ \t]*$")
    m = ap.search(text)
    if m:
        print(f"    {key} = {raw_value}  (agregada)")
        return (
            text[: m.end()]
            + f"\n{key} = {raw_value}"
            + text[m.end():]
        )
    print(f"    [appearance] creada con {key} = {raw_value}")
    return f'[appearance]\n{key} = {raw_value}\n\n' + text.lstrip()

text = set_scalar(text, "hide_logo", "true")
text = set_scalar(text, "power_buttons_position", '"bottom-right"')

# Se reemplaza la seccion global si existe; si no, se agrega al final.
new_section = (
    "[appearance.wallpaper]\n"
    f'path = "{wallpaper}"\n'
    "fill_mode = 0\n"
    "\n"
)

pattern = re.compile(
    r"^\[appearance\.wallpaper\][^\[]*", re.MULTILINE | re.DOTALL
)
if pattern.search(text):
    text = pattern.sub(new_section, text, count=1)
    print("    seccion [appearance.wallpaper] reemplazada")
else:
    text = text.rstrip() + "\n\n" + new_section
    print("    seccion [appearance.wallpaper] agregada")

if removed:
    print(f"    fuera {removed} override(s) por pantalla (tenian prioridad)")
else:
    print("    no habia overrides por pantalla")

open(dst, "w").write(text)
PY

echo
echo "    --- greeter.toml resultante (seccion del wallpaper) ---"
python3 - "$STAGING/greeter.toml" <<'PY' | sed 's/^/    /'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"^\[appearance\.wallpaper\].*?(?=^\[|\Z)", t, re.M | re.S)
print(m.group(0).strip() if m else "(no encontrada)")
PY

# El TOML tiene que ser parseable antes de tocar el sistema
python3 -c "
import tomllib, sys
tomllib.load(open('$STAGING/greeter.toml','rb'))
print('    TOML valido')
" || die "el TOML generado no parsea, no se instala nada"

# ------------------------------------------------- 4. aplicar
log "4/5  Instalando en /var/lib/noctalia-greeter"
if /usr/bin/noctalia-greeter-apply-appearance "$STAGING" 2>&1 | sed 's/^/    /'; then
    ok "apply-appearance termino sin error"
else
    warn "apply-appearance fallo, se restaura el respaldo"
    cp -a "$BACKUP" "$TOML"
    die "restaurado. Nada quedo cambiado."
fi

# Verificacion de verdad: el archivo instalado tiene la ruta nueva
if [ -f "$TOML" ] && grep -q "$DEST" "$TOML"; then
    ok "verificado: greeter.toml apunta a $DEST"
else
    warn "el archivo instalado no contiene la ruta esperada:"
    sudo cat "$TOML" 2>/dev/null | head -20 | sed 's/^/      /'
fi

# El directorio de estado es del usuario greeter: nada de 644 en un archivo
# que ese usuario tiene que escribir.
chown greeter:greeter "$STATE" 2>/dev/null || true
chown greeter:greeter "$TOML" 2>/dev/null || true
chmod 750 "$STATE" 2>/dev/null || true
chmod 600 "$TOML" 2>/dev/null || true
ok "propietario y permisos del estado ajustados a greeter:greeter"

# ------------------------------------------------- 5. sync automatico
log "5/5  Activando el sync automatico de apariencia"
if /usr/bin/noctalia-greeter passwordless-sync enable omicron 2>&1 | sed 's/^/    /'; then
    ok "sync activado: el greeter puede tomar la apariencia de la sesion"
else
    warn "no se pudo activar el sync (no es bloqueante: el wallpaper ya quedo fijo)"
fi

rm -rf "$STAGING"

log "Listo"
cat <<EOF
  Como comprobarlo:
    1. Bloquea la pantalla (Super+L). Ahi deberia verse tu wallpaper.
    2. Para el login: cerrá la sesion. El greeter aparece en la TTY.
       Solo se puede ver de verdad saliendo de la sesion, no hay forma de
       recargar el greeter en caliente.

  La copia en /usr/share/backgrounds/login-wallpaper.png es la que usa el
  greeter. Si despues cambias de wallpaper en tu sesion, actualiza esa copia:

    sudo install -m 0644 -o root -g root "/ruta/nuevo.png" /usr/share/backgrounds/login-wallpaper.png

  Respaldo del config anterior:
    $BACKUP
EOF