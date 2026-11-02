#!/bin/bash

# Battery notification script - reduce brightness and switch to the power-saver
# profile when battery is low, and put both back when the charger goes in.
# Run by a systemd timer every 30 seconds, and by the bar at the moment the
# charger is plugged in or pulled out.

BATTERY_THRESHOLD=(20 15 10 5 3)
# Brightness to drop to once the battery reaches the first threshold. Fixed on
# purpose: dimming hard and early buys more runtime than stepping down slowly.
LOW_BATTERY_BRIGHTNESS=5
# The threshold last acted on, so a crossing acts once. Overridable for the
# same reason as the record below: a suite that ran against the real path
# deleted the live flag out from under the running service.
FLAG_FILE="${HYPRSIMPLE_BATTERY_FLAG:-/tmp/battery-notification-flag}"
# Where the brightness was before a low battery dimmed the screen, so charging
# can put it back. Beside the flag, and overridable so the suite never writes
# to the real one.
BRIGHTNESS_FILE="${HYPRSIMPLE_BRIGHTNESS_FILE:-/tmp/battery-brightness-before-dim}"
# The power profile to switch to with the dimming, and where the one in use
# before is kept so charging can put it back.
#
# Not in /tmp like the two above. power-profiles-daemon keeps its profile
# across a reboot and /tmp does not, so a machine that ran flat in power-saver
# would come back still in it, with the record of what to return to gone.
LOW_BATTERY_PROFILE=power-saver
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprsimple"
PROFILE_FILE="${HYPRSIMPLE_PROFILE_FILE:-$STATE_DIR/battery-profile-before-low}"

get_battery_percentage() {
  upower -i "$(upower -e | grep 'BAT')" |
    awk -F: '/percentage/ {
      gsub(/[%[:space:]]/, "", $2);
      val=$2;
      printf("%d\n", (val+0.5))
      exit
    }'
}

get_battery_state() {
  upower -i "$(upower -e | grep 'BAT')" | grep -E "state" | awk '{print $2}'
}

BATTERY_LEVEL=$(get_battery_percentage)
BATTERY_STATE=$(get_battery_state)

LAST_AC_STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/last-ac-state"

is_ac_connected() {
  for f in /sys/class/power_supply/*/online; do
    if [[ -f "$f" && $(cat "$f" 2>/dev/null) == "1" ]]; then
      echo 1
      return
    fi
  done
  if [[ "$BATTERY_STATE" =~ ^(charging|fully-charged)$ ]]; then
    echo 1
    return
  fi
  echo 0
}

AC_CONNECTED=$(is_ac_connected)
LAST_AC=$(cat "$LAST_AC_STATE_FILE" 2>/dev/null || echo "")

if [[ "$AC_CONNECTED" == "1" ]]; then
  # ============================================================================
  # Cargador Conectado (AC) -> MODO GAMER / MAXIMO RENDIMIENTO
  # ============================================================================
  rm -f "$FLAG_FILE"

  if [[ "$LAST_AC" != "1" ]]; then
    if command -v powerprofilesctl >/dev/null 2>&1; then
      cur_profile=$(powerprofilesctl get 2>/dev/null)
      if [[ "$cur_profile" != "performance" ]]; then
        powerprofilesctl set performance
      fi
    fi

    # Invocar power-state-manager si está disponible con permisos sudoers
    sudo -n /usr/local/bin/power-state-manager ac 2>/dev/null || true

    # Restaurar brillo si habia sido atenuado por bateria baja previa
    if [[ -f $BRIGHTNESS_FILE ]]; then
      saved=$(cat "$BRIGHTNESS_FILE" 2>/dev/null)
      now=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
      if [[ $saved =~ ^[0-9]+$ && $now =~ ^[0-9]+$ ]] && ((now < saved)); then
        brightnessctl set "${saved}%"
      fi
      rm -f "$BRIGHTNESS_FILE"
    fi
    rm -f "$PROFILE_FILE"

    notify-send -a "Energía" -i "battery-charging" "⚡ Modo Rendimiento Gamer" "Cargador conectado: Turbo hasta 3.8 GHz, GPU optimizada a 1250 MHz y disipación activa." -u normal -t 3500
    echo "1" > "$LAST_AC_STATE_FILE"
  fi

else
  # ============================================================================
  # Funcionando con Bateria
  # ============================================================================
  if [[ "$LAST_AC" == "1" ]]; then
    # Desconexion del cargador -> Retornar a modo equilibrado y eficiente
    if command -v powerprofilesctl >/dev/null 2>&1; then
      powerprofilesctl set balanced
    fi
    sudo -n /usr/local/bin/power-state-manager battery 2>/dev/null || true
    notify-send -a "Energía" -i "battery" "🔋 Modo Batería Eficiente" "Cargador desconectado: Perfil balanceado para optimizar autonomía y temperatura." -u normal -t 3500
    echo "0" > "$LAST_AC_STATE_FILE"
  elif [[ -z "$LAST_AC" ]]; then
    echo "0" > "$LAST_AC_STATE_FILE"
  fi

  # Gestion de umbrales criticos de bateria
  crossed=""
  for threshold in "${BATTERY_THRESHOLD[@]}"; do
    if [[ "$BATTERY_LEVEL" -le "$threshold" ]] &&
      { [[ -z $crossed ]] || [[ "$threshold" -lt "$crossed" ]]; }; then
      crossed="$threshold"
    fi
  done

  if [[ -n $crossed ]]; then
    if [[ ! -f "$FLAG_FILE" ]] || [[ $(cat "$FLAG_FILE" 2>/dev/null) != "$crossed" ]]; then
      recorded=$(cat "$BRIGHTNESS_FILE" 2>/dev/null)
      now=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
      if [[ $now != "$LOW_BATTERY_BRIGHTNESS" ]]; then
        if [[ ! $recorded =~ ^[0-9]+$ ]]; then
          printf '%s\n' "$now" >"$BRIGHTNESS_FILE"
        fi
        brightnessctl set "${LOW_BATTERY_BRIGHTNESS}"%
      fi

      if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl set "$LOW_BATTERY_PROFILE"
      fi
      notify-send -u critical "Batería Baja" "Batería al ${BATTERY_LEVEL}%, brillo reducido y ahorro de energía activado."
      echo "$crossed" >"$FLAG_FILE"
    fi
  fi
fi
