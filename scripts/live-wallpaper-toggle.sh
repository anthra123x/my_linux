#!/bin/bash

# Toggle live wallpaper (hyprpaper directory cycling)
# When ON: hyprpaper cycles through theme backgrounds every 30s
# When OFF: hyprpaper shows a single static wallpaper

CACHE_DIR="$HOME/.cache"
FLAG="$CACHE_DIR/live_wallpaper_enabled"

# This one line cannot use require_helper, so it carries the check itself.
source "$HOME/.local/bin/hyprsimple-require.sh" 2>/dev/null || {
  echo "hyprsimple: missing helper: hyprsimple-require.sh. Run hyprsimple-update." >&2
  command -v notify-send >/dev/null &&
    notify-send -u critical "hyprsimple" "Missing helper: hyprsimple-require.sh. Run hyprsimple-update."
  exit 1
}
require_helper hypr-helpers.sh

# Derive backgrounds dir from current wallpaper path
CURRENT_PATH=$(cat "$CACHE_DIR/current_wallpaper_path" 2>/dev/null)
THEME_DIR=$(dirname "$(dirname "$CURRENT_PATH")" 2>/dev/null)
BG_DIR="$THEME_DIR/backgrounds"

if [[ ! -d "$BG_DIR" ]]; then
  notify-send "Live Wallpaper" "No backgrounds folder found for current theme"
  exit 1
fi

ACTION="$1"

# Restart hyprpaper and say whether it took.
#
# Both branches below used to run the restart unchecked and notify regardless,
# so a hyprpaper that would not come back left the user told live wallpaper was
# on while nothing was cycling. Measured with a systemctl that fails:
# "Enabled (30s cycle)", exit 0.
#
# The setting itself is already written by then, and that part did work, so the
# message says the state was recorded and names the half that did not happen
# rather than pretending nothing was done.
reload_hyprpaper() {
  systemctl --user restart hyprpaper.service 2>/dev/null
}

turn_off() {
  mkdir -p "$HOME/.config/wallmotion"
  echo "static" > "$HOME/.config/wallmotion/mode" 2>/dev/null || true
  echo "static" > "$CACHE_DIR/wallpaper_type" 2>/dev/null || true
  if pgrep -x mpvpaper >/dev/null 2>&1; then
    "$HOME/.local/bin/wallmotion" stop >/dev/null 2>&1 || true
  fi
  # Try to get current wallpaper from hyprpaper IPC
  ACTIVE=$(hyprctl hyprpaper listactive 2>/dev/null | head -1)
  # Parse: hyprpaper answers "monitor: /path/to/wallpaper". It was read here as
  # "monitor = /path", so the strip matched nothing, the path kept its "eDP-1: "
  # prefix, the -f check below rejected it, and every disable fell back to the
  # cached wallpaper. That is the exact staleness this lookup exists to avoid.
  RESOLVED="${ACTIVE#*: }"

  # Validate resolved path exists and is inside the theme backgrounds dir
  if [[ ! -f "$RESOLVED" || "$RESOLVED" != "$BG_DIR"/* ]]; then
    # Fallback to cached path
    RESOLVED="$CURRENT_PATH"
  fi

  if [[ -f "$RESOLVED" ]]; then
    rm -f "$CACHE_DIR/current_wallpaper"
    cp "$RESOLVED" "$CACHE_DIR/current_wallpaper"
    echo "$RESOLVED" > "$CACHE_DIR/current_wallpaper_path"
  fi

  write_hyprpaper_conf "$HOME/.cache/current_wallpaper"
  rm -f "$FLAG"
  if reload_hyprpaper; then
    notify-send "Live Wallpaper" "Disabled" -i "$CACHE_DIR/current_wallpaper"
  else
    notify-send -u critical "Live Wallpaper" "Disabled, but hyprpaper did not restart, so the screen still shows the old one until you log in again"
    exit 1
  fi
}

turn_on() {
  mkdir -p "$HOME/.config/wallmotion"
  echo "static" > "$HOME/.config/wallmotion/mode" 2>/dev/null || true
  echo "static" > "$CACHE_DIR/wallpaper_type" 2>/dev/null || true
  if pgrep -x mpvpaper >/dev/null 2>&1; then
    "$HOME/.local/bin/wallmotion" stop >/dev/null 2>&1 || true
  fi
  write_hyprpaper_conf "$BG_DIR" 30
  touch "$FLAG"
  if reload_hyprpaper; then
    notify-send "Live Wallpaper" "Enabled (30s cycle)" -i "$CACHE_DIR/current_wallpaper"
  else
    notify-send -u critical "Live Wallpaper" "Enabled, but hyprpaper did not restart, so nothing cycles until you log in again"
    exit 1
  fi
}

case "$ACTION" in
  apply)
    # Comprobar si el modo guardado es animado (wallmotion)
    MODE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/wallmotion/mode"
    CACHE_MODE="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper_type"
    STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/wallmotion/state.json"

    IS_ANIMATED=0
    if [[ -f "$MODE_FILE" && "$(cat "$MODE_FILE" 2>/dev/null)" == "animated" ]]; then
      IS_ANIMATED=1
    elif [[ -f "$CACHE_MODE" && "$(cat "$CACHE_MODE" 2>/dev/null)" == "animated" ]]; then
      IS_ANIMATED=1
    elif [[ ! -f "$MODE_FILE" && ! -f "$CACHE_MODE" && -f "$STATE_FILE" ]]; then
      CURR=$(python3 -c 'import json; d=json.load(open("'"$STATE_FILE"'")); print("yes" if d.get("current") and not d.get("paused") else "no")' 2>/dev/null || echo "no")
      [[ "$CURR" == "yes" ]] && IS_ANIMATED=1
    fi

    if (( IS_ANIMATED )); then
      systemctl --user stop hyprpaper.service >/dev/null 2>&1 || true
      if [[ -x "$HOME/.local/bin/wallmotion" ]]; then
        "$HOME/.local/bin/wallmotion" restore >/dev/null 2>&1 || "$HOME/.local/bin/wallmotion" play >/dev/null 2>&1 || true
      fi
      exit 0
    fi

    if pgrep -x mpvpaper >/dev/null 2>&1; then
      "$HOME/.local/bin/wallmotion" stop >/dev/null 2>&1 || true
    fi
    # Put hyprpaper in whatever state the flag already records, without
    # changing that state. This is what autostart wants at login.
    #
    # It used to run "on" there, which turned live wallpaper back on every
    # single login. Turning it off with SUPER+CTRL+W lasted until the next one,
    # and so did picking a wallpaper with SUPER+W, because that clears the same
    # flag to pin the choice. A toggle whose state is reset at every login is
    # not a toggle.
    if [[ -f "$FLAG" ]]; then
      write_hyprpaper_conf "$BG_DIR" 30
    else
      write_hyprpaper_conf "$HOME/.cache/current_wallpaper"
    fi
    systemctl --user restart hyprpaper.service 2>/dev/null || true
    ;;
  on)
    # Skip if already on
    [[ -f "$FLAG" ]] && exit 0
    turn_on
    ;;
  off)
    # Skip if already off
    [[ ! -f "$FLAG" ]] && exit 0
    turn_off
    ;;
  *)
    # Toggle (original behavior)
    if [[ -f "$FLAG" ]]; then
      turn_off
    else
      turn_on
    fi
    ;;
esac
