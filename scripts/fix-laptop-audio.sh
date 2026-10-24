#!/usr/bin/env bash
#
# Fuerza la salida analoga integrada (altavoces internos) en portatiles ASUS
# con SOF (Vivobook E1504GA / Alder Lake-N).
#
# Por que hace falta:
#   La tarjeta ALSA expone analogico y 3 salidas HDMI en un solo dispositivo.
#   El perfil HiFi de mayor prioridad es "HiFi (..., Headphones, ...)" (10300),
#   que gana siempre sobre "HiFi (..., Speaker, ...)" (10200). Al quedar el
#   perfil de los altavoces internos sin seleccionar, el firmware SOF deja el
#   amplificador "Speaker" en mute ([off]), y el audio se rutea al HDMI.
#
# Es idempotente: no cambia nada si ya esta todo correcto.

set -u

CARD="alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic"
PROFILE="HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)"
SINK="alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink"

AMP_PCT=90   # nivel del amplificador analogico (~-6.75 dB, sin clipping)
VOL_PCT=80   # volumen de la aplicacion en PipeWire

log() { printf '[fix-audio] %s\n' "$*" >&2; }

# Espera a que la tarjeta de audio aparezca (tarda unos segundos al arrancar).
for _ in $(seq 1 30); do
    pactl list cards 2>/dev/null | grep -q "$CARD" && break
    sleep 1
done

if ! pactl list cards 2>/dev/null | grep -q "$CARD"; then
    log "tarjeta $CARD no encontrada; abortando"
    exit 1
fi

# 1) Seleccionar el perfil que incluye los altavoces internos.
current=$(pactl list cards 2>/dev/null | sed -n 's/^[[:space:]]*Active Profile: //p')
if [ "$current" != "$PROFILE" ]; then
    if pactl set-card-profile "$CARD" "$PROFILE" 2>/dev/null; then
        log "perfil: '${current:-?}' -> '$PROFILE'"
        sleep 1
    else
        log "no se pudo cambiar el perfil; continuando"
    fi
fi

# 2) Desmutear el amplificador de altavoces. El cambio de perfil lo revierte a
#    mute, asi que hay que hacerlo despues del paso 1.
if command -v amixer >/dev/null 2>&1; then
    amixer -c 0 sset 'Speaker' "$AMP_PCT"% unmute >/dev/null 2>&1 \
        && log "amplificador Speaker: ${AMP_PCT}% unmute"
fi

# 3) Altavoces internos como salida por defecto.
if pactl list sinks 2>/dev/null | grep -q "$SINK"; then
    pactl set-sink-mute "$SINK" 0 >/dev/null 2>&1
    pactl set-sink-volume "$SINK" "$VOL_PCT"% >/dev/null 2>&1
    pactl set-default-sink "$SINK" >/dev/null 2>&1
    log "salida por defecto: $(pactl get-default-sink 2>/dev/null || echo '?')"
else
    log "sink $SINK no disponible"
    exit 1
fi
