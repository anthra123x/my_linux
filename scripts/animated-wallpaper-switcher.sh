#!/bin/bash
# ==============================================================================
# animated-wallpaper-switcher.sh
# ==============================================================================
# Controlador y conmutador de fondos animados para Hyprland y Quickshell.
# Se integra con el motor 'wallmotion' (mpvpaper + VAAPI).
#
# Uso:
#   animated-wallpaper-switcher.sh [pick|apply <id>|current|add|delete <id>|is-running|toggle-stop [on|off]]
#
# Acciones:
#   pick         - Despliega el carrusel de fondos animados en la barra de Quickshell.
#   apply <id>   - Reproduce el fondo animado seleccionado mediante wallmotion.
#   current      - Imprime el identificador del fondo animado activo.
#   add          - Abre diálogo gráfico (zenity) para importar un nuevo vídeo a la biblioteca.
#   delete <id>  - Elimina el vídeo y miniatura de la biblioteca.
#   is-running   - Sale con código 0 si mpvpaper está en ejecución, 1 si no.
#   toggle-stop  - Conmuta o detiene/reanuda la reproducción del fondo animado.
# ==============================================================================

set -eo pipefail

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallmotion"
STATE_FILE="$CFG_DIR/state.json"
THUMBS_DIR="$CFG_DIR/thumbs"
WALLMOTION_BIN="$HOME/.local/bin/wallmotion"

# Comprobar que wallmotion existe
if [[ ! -x "$WALLMOTION_BIN" ]]; then
  command -v notify-send >/dev/null 2>&1 &&
    notify-send -u critical "Fondo animado" "No se encontró el ejecutable wallmotion en $WALLMOTION_BIN"
  echo "Error: wallmotion no encontrado en $WALLMOTION_BIN" >&2
  exit 1
fi

ACTION="${1:-pick}"

case "$ACTION" in
  pick)
    # Abre el panel de fondos animados en Quickshell
    exec qs -p "${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell" ipc call bar toggle animated_wallpapers
    ;;

  apply)
    ID="$2"
    if [[ -z "$ID" ]]; then
      echo "Uso: $0 apply <id>" >&2
      exit 1
    fi
    "$WALLMOTION_BIN" play "$ID"
    THUMB="$THUMBS_DIR/$ID.jpg"
    if [[ -f "$THUMB" ]]; then
      notify-send "Fondo animado" "Fondo aplicado: $ID" -i "$THUMB" 2>/dev/null || true
    else
      notify-send "Fondo animado" "Fondo aplicado: $ID" 2>/dev/null || true
    fi
    ;;

  current)
    if pgrep -x mpvpaper >/dev/null 2>&1; then
      if [[ -f "$STATE_FILE" ]]; then
        python3 -c '
import json, sys
from pathlib import Path
try:
    data = json.loads(Path("'"$STATE_FILE"'").read_text("utf-8"))
    print(data.get("current") or "")
except Exception:
    pass
'
      fi
    fi
    ;;

  add)
    if ! command -v zenity >/dev/null 2>&1; then
      notify-send -u critical "Fondo animado" "zenity no está instalado para seleccionar el archivo."
      exit 1
    fi
    CHOSEN=$(zenity --file-selection --title="Añadir fondo animado" \
      --file-filter="Vídeos | *.mp4 *.webm *.mkv *.mov *.gif *.ogv *.MP4 *.WEBM *.MKV *.MOV *.GIF *.OGV" 2>/dev/null) || exit 0
    [[ -n "$CHOSEN" ]] || exit 0

    if [[ ! -f "$CHOSEN" ]]; then
      notify-send "Fondo animado" "El archivo seleccionado no existe: $CHOSEN"
      exit 1
    fi

    "$WALLMOTION_BIN" add "$CHOSEN"
    notify-send "Fondo animado" "Nuevo fondo añadido a la biblioteca: $(basename "$CHOSEN")" 2>/dev/null || true
    ;;

  delete)
    ID="$2"
    if [[ -z "$ID" ]]; then
      echo "Uso: $0 delete <id>" >&2
      exit 1
    fi
    # Si el fondo a eliminar está en reproducción activa, detenerlo primero
    CURRENT_ID=$("$0" current || true)
    if [[ "$CURRENT_ID" == "$ID" ]]; then
      "$WALLMOTION_BIN" stop >/dev/null 2>&1 || true
    fi
    "$WALLMOTION_BIN" rm "$ID"
    notify-send "Fondo animado" "Fondo eliminado de la biblioteca: $ID" 2>/dev/null || true
    ;;

  is-running)
    if pgrep -x mpvpaper >/dev/null 2>&1; then
      exit 0
    else
      exit 1
    fi
    ;;

  toggle-stop)
    PARAM="${2:-}"
    if [[ "$PARAM" == "off" ]]; then
      "$WALLMOTION_BIN" stop >/dev/null 2>&1 || true
      systemctl --user start hyprpaper.service >/dev/null 2>&1 || true
      notify-send "Fondo animado" "Reproducción detenida" 2>/dev/null || true
    elif [[ "$PARAM" == "on" ]]; then
      "$WALLMOTION_BIN" restore >/dev/null 2>&1 || "$WALLMOTION_BIN" play >/dev/null 2>&1 || true
      notify-send "Fondo animado" "Reproducción reanudada" 2>/dev/null || true
    else
      if pgrep -x mpvpaper >/dev/null 2>&1; then
        "$WALLMOTION_BIN" stop >/dev/null 2>&1 || true
        systemctl --user start hyprpaper.service >/dev/null 2>&1 || true
        notify-send "Fondo animado" "Reproducción detenida" 2>/dev/null || true
      else
        "$WALLMOTION_BIN" restore >/dev/null 2>&1 || "$WALLMOTION_BIN" play >/dev/null 2>&1 || true
        notify-send "Fondo animado" "Reproducción reanudada" 2>/dev/null || true
      fi
    fi
    ;;

  *)
    echo "Opción no reconocida: $ACTION" >&2
    echo "Uso: $0 [pick|apply <id>|current|add|delete <id>|is-running|toggle-stop]" >&2
    exit 1
    ;;
esac

