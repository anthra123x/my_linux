# Modulo de Audio PipeWire: DSP y Filtros

## 1. Proposito y alcance
Gestiona la configuracion de procesamiento acustico en tiempo real (DSP) y ecualizacion inteligente para el hardware de audio del sistema (PipeWire / WirePlumber), con foco en la compensacion acustica, erradicacion de resonancia de chasis plastico ("plasticosa"), calidez en medios-altos y optimizacion psicoacustica de graves para los altavoces integrados de la laptop ASUS Vivobook Go E1504GA.

## 2. Contratos y API
- **Filtro inteligente WirePlumber**: `filter.smart = true`, `filter.smart.name = "laptop_speaker_dsp"`, `node.link-group = "laptop_speaker_dsp"`
- **Target especifico**: `filter.smart.target = "{ \"node.name\": \"alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink\" }"`
- **Nodo de captura (Virtual Sink)**: `effect_input.laptop_speaker_dsp` (`media.class = Audio/Sink`, `node.link-group = "laptop_speaker_dsp"`)
- **Nodo de reproduccion**: `effect_output.laptop_speaker_dsp` (`node.passive = true`, `node.link-group = "laptop_speaker_dsp"`)
- **Cadena de filtros acusticos (Biquad & Linear)**:
  - `preamp`: `linear` (Mult: 0.531 = -5.5 dB headroom digital contra distorsion y clipping DAC).
  - `eq_hpf`: `bq_highpass` (60.0 Hz, Q: 0.707) corte subsonico y proteccion contra flutter/sobre-excursion.
  - `eq_bass_punch`: `bq_peaking` (115.0 Hz, Q: 1.2, Gain: +6.5 dB) presencia, impacto y pegada de graves a bajo volumen.
  - `eq_bass_warmth`: `bq_peaking` (200.0 Hz, Q: 1.3, Gain: +5.0 dB) contorno de igual sonoridad (Fletcher-Munson) y cuerpo acustico.
  - `eq_debox`: `bq_peaking` (450.0 Hz, Q: 1.6, Gain: -4.5 dB) atenuacion critica de resonancia acustica del chasis plastico.
  - `eq_decan`: `bq_peaking` (850.0 Hz, Q: 1.8, Gain: -3.0 dB) reduccion de resonancia de cavidad hueca / sonido a lata.
  - `eq_mid_body`: `bq_peaking` (1200.0 Hz, Q: 1.0, Gain: +1.0 dB) estabilizacion y calidez en el rango vocal central.
  - `eq_deharsh`: `bq_peaking` (3200.0 Hz, Q: 1.6, Gain: -3.5 dB) eliminacion de picos por ruptura de cono (cone breakup) y fatiga auditiva ("demasiado claro").
  - `eq_desibilance`: `bq_peaking` (6200.0 Hz, Q: 2.0, Gain: -3.5 dB) suavizado de sibilancias y asperezas en frecuencias altas.
  - `eq_warm_top`: `bq_highshelf` (8500.0 Hz, Q: 0.707, Gain: -2.5 dB) caida suave y sedosa en agudos para evitar sonido estridente.

## 3. Dependencias
- `pipewire` (version >= 1.0, modulo `libpipewire-module-filter-chain`).
- `wireplumber` (version >= 0.5 con soporte de smart filters).
- `spa-plugins`: `filter-graph-plugin-builtin` (incluido en instalacion nativa de PipeWire).
- Direccion de dependencia: `Aplicaciones -> WirePlumber Smart Link -> effect_input -> DSP Biquad Chain -> effect_output -> ALSA Speaker Sink`. Dispositivos externos (HDMI, Bluetooth, auriculares) omiten el filtro automaticamente.

## 4. Mapa de archivos
- `pipewire.conf.d/50-laptop-speaker-dsp.conf`: Definicion del modulo filter-chain y grafos biquad de procesamiento acustico activo.
- `pipewire.conf.d/99-input-denoising.conf.disabled`: Filtro opcional de cancelacion de ruido de microfono (LADSPA RNNoise).
- `README.md`: Documentacion del modulo y contratos tecnicos del agente.

## 5. Logica y flujo
1. WirePlumber detecta el nodo de altavoz de hardware (`alsa_output...HiFi__Speaker__sink`).
2. PipeWire carga `50-laptop-speaker-dsp.conf` instanciando `effect_input.laptop_speaker_dsp` y `effect_output.laptop_speaker_dsp`.
3. El script de linking `find-filter-target.lua` y `get-filter-from-target.lua` enlaza `effect_output` directamente hacia el sink fisico ALSA Speaker.
4. Cuando un cliente de audio reproduce hacia el altavoz por defecto, WirePlumber intercepta el flujo y lo conecta a `effect_input`, procesando la senal a traves de la cadena biquad.
5. Al alternar hacia auriculares o dispositivo Bluetooth, el target fisico cambia; WirePlumber conmuta los enlaces sin activar el DSP en los perifericos externos.

## 6. Decisiones de diseño y gotchas
- **Aislamiento exclusivo para la laptop**: Se utiliza `filter.smart.target` apuntando unicamente al nodo ALSA de los altavoces de la laptop. Al conectar auriculares o Bluetooth, WirePlumber cambia el target y no aplica este procesado.
- **Sincronizacion de `node.link-group`**: WirePlumber 0.5 exige que tanto `capture.props` como `playback.props` compartan `node.link-group` identico para asociar el session item principal con el stream de salida.
- **Prevencion de distorsion a volumen alto**: Los micro-altavoces de laptop distorsionan si se intenta reproducir sub-graves (<60 Hz). El filtro paso-alto a 60 Hz limpia esa energia inutil y el preamp a -5.5 dB garantiza margen digital suficiente ante los realces de graves a 115 Hz y 200 Hz.
- **Eliminacion de caracter plasticoso y excesivo brillo**: Se recortan 450 Hz y 850 Hz para eliminar la resonancia de caja plastica, y se reemplaza el antiguo realce de agudos por un high-shelf descendente a 8500 Hz para otorgar un perfil acustico calido y suave.

## 7. Estado y ultimos cambios
- Activacion del DSP tras haber estado deshabilitado en `.disabled`.
- Reconfiguracion de curvas: HPF a 60 Hz, graves en 115 Hz (+6.5 dB) y 200 Hz (+5.0 dB), atenuacion de resonancia plastica en 450 Hz (-4.5 dB) y 850 Hz (-3.0 dB), control de aspereza en 3200 Hz (-3.5 dB) y 6200 Hz (-3.5 dB), y roll-off calido a 8500 Hz (-2.5 dB).
- Preamp ajustado a 0.531 (-5.5 dB) con validacion sintactica en `spa-json-dump`.

## 8. Como verificar
- **Verificar estado de nodos**: `wpctl status | grep -A 4 Filters`
- **Inspeccionar enlaces activos**: `pw-link -l`
- **Verificar latencia y errores**: `pw-top -b -n 2`
- **Recargar configuracion**: `systemctl --user restart pipewire wireplumber`
