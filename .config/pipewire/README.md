# Modulo de Audio PipeWire: DSP y Filtros

## 1. Proposito y alcance
Gestiona la configuracion de procesamiento acustico en tiempo real (DSP) y ecualizacion inteligente para el hardware de audio del sistema (PipeWire / WirePlumber), con foco en la compensacion acustica y optimizacion de graves para los altavoces integrados de la laptop.

## 2. Contratos
- **Filtro inteligente WirePlumber**: `filter.smart = true`, `filter.smart.name = "laptop_speaker_dsp"`
- **Target especifico**: `filter.smart.target = { "node.name": "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink" }`
- **Nodo de captura (Virtual Sink)**: `effect_input.laptop_speaker_dsp` (`media.class = Audio/Sink`)
- **Nodo de reproduccion**: `effect_output.laptop_speaker_dsp` (`node.passive = true`)
- **Cadena de filtros acusticos (Biquad & Linear)**:
  - `preamp`: `linear` (Mult: 0.631 = -4.0 dB headroom digital).
  - `eq_hpf`: `bq_highpass` (65 Hz, Q: 0.707) proteccion contra flutter/sobre-excursion.
  - `eq_bass_punch`: `bq_peaking` (135 Hz, Q: 1.3, Gain: +5.5 dB) presencia y pegada de graves.
  - `eq_bass_warmth`: `bq_peaking` (220 Hz, Q: 1.4, Gain: +3.5 dB) contorno de igual sonoridad (Fletcher-Munson a volumen bajo).
  - `eq_debox`: `bq_peaking` (480 Hz, Q: 1.5, Gain: -3.0 dB) atenuacion de resonancia de chasis de plastico.
  - `eq_vocal`: `bq_peaking` (2000 Hz, Q: 1.2, Gain: +1.5 dB) claridad y presencia de voces.
  - `eq_deharsh`: `bq_peaking` (7000 Hz, Q: 2.0, Gain: -2.5 dB) suavizado de sibilancias y agudos asperos.
  - `eq_air`: `bq_highshelf` (11000 Hz, Q: 0.707, Gain: +2.5 dB) apertura y brillo Hi-Fi.

## 3. Dependencias
- `pipewire` (version >= 1.0, modulo `libpipewire-module-filter-chain`).
- `wireplumber` (version >= 0.5 con soporte de smart filters).
- `spa-plugins`: `filter-graph-plugin-builtin` (incluido en instalacion nativa de PipeWire).
- Direccion de dependencia: `Aplicaciones -> WirePlumber Smart Link -> effect_input -> DSP Biquad Chain -> effect_output -> ALSA Speaker Sink`. Dispositivos externos (HDMI, Bluetooth, auriculares) omiten el filtro automaticamente.

## 4. Mapa de archivos
- `pipewire.conf.d/50-laptop-speaker-dsp.conf`: Definicion del modulo filter-chain y grafos biquad de procesamiento.
- `pipewire.conf.d/99-input-denoising.conf.disabled`: Filtro opcional de cancelacion de ruido de microfono (LADSPA RNNoise).
- `README.md`: Documentacion del modulo y contratos tecnicos.

## 5. Decisiones y gotchas
- **Aislamiento exclusivo para la laptop**: Se utiliza `filter.smart.target` apuntando unicamente al nodo ALSA de los altavoces de la laptop. Al conectar auriculares o Bluetooth, WirePlumber cambia el target y no aplica este procesado.
- **Evitar distorsion a volumen alto**: Los micro-altavoces de laptop distorsionan si se intenta reproducir sub-graves (<60 Hz). El filtro paso-alto a 65 Hz limpia esa energia inutil y el preamp a -4 dB evita cualquier recorte digital (clipping) a 100% de volumen.

## 6. Como verificar
- **Verificar estado de nodos**: `wpctl status | grep -A 4 Filters`
- **Inspeccionar enlaces activos**: `pw-link -l`
- **Verificar latencia y errores**: `pw-top -b -n 2`
- **Recargar configuracion**: `systemctl --user restart pipewire wireplumber`

