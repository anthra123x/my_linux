#!/usr/bin/env bash
# ==============================================================================
# wallpaper-restore.sh - Restaurador persistente de fondos para Omicron Shell
# ==============================================================================
# Determina si el último fondo activo fue animado (wallmotion) o estático (hyprpaper)
# y reanuda el estado exacto sin colisión de capas ni ejecuciones redundantes.
# ==============================================================================

set -euo pipefail

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wallmotion"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
MODE_FILE="$CFG_DIR/mode"
CACHE_MODE="$CACHE_DIR/wallpaper_type"
STATE_FILE="$CFG_DIR/state.json"
WALLMOTION_BIN="$HOME/.local/bin/wallmotion"
LIVE_TOGGLE_BIN="$HOME/.local/bin/live-wallpaper-toggle.sh"

IS_ANIMATED=0
if [[ -f "$MODE_FILE" ]]; then
  [[ "$(cat "$MODE_FILE" 2>/dev/null)" == "animated" ]] && IS_ANIMATED=1
elif [[ -f "$CACHE_MODE" ]]; then
  [[ "$(cat "$CACHE_MODE" 2>/dev/null)" == "animated" ]] && IS_ANIMATED=1
elif [[ -f "$STATE_FILE" ]]; then
  CURR=$(python3 -c 'import json; d=json.load(open("'"$STATE_FILE"'")); print("yes" if d.get("current") and not d.get("paused") else "no")' 2>/dev/null || echo "no")
  [[ "$CURR" == "yes" ]] && IS_ANIMATED=1
fi

if (( IS_ANIMATED )) && [[ -x "$WALLMOTION_BIN" ]]; then
  # 1. Modo animado persistente: detener hyprpaper y restaurar mpvpaper con VAAPI
  systemctl --user stop hyprpaper.service >/dev/null 2>&1 || true
  "$WALLMOTION_BIN" restore >/dev/null 2>&1 || "$WALLMOTION_BIN" play >/dev/null 2>&1 || true
else
  # 2. Modo estático: asegurar que wallmotion no compita y restaurar hyprpaper
  if pgrep -x mpvpaper >/dev/null 2>&1; then
    [[ -x "$WALLMOTION_BIN" ]] && "$WALLMOTION_BIN" stop >/dev/null 2>&1 || true
  fi
  if [[ -x "$LIVE_TOGGLE_BIN" ]]; then
    "$LIVE_TOGGLE_BIN" apply >/dev/null 2>&1 || true
  else
    systemctl --user start hyprpaper.service >/dev/null 2>&1 || true
  fi
fi
