# Quickshell UI (Omicron Shell)

## 1. Proposito y Alcance
Provee la suite de interfaz de usuario de escritorio en Wayland mediante Quickshell para Hyprland. Incluye la barra superior de estado con capsulas flotantes independientes sin fondo solido ni desenfoque transversal, la isla dinamica central (Dynamic Island) con reproductor de musica expandible al estilo iOS, selector de areas de trabajo, monitores de recursos del sistema, controles de audio PipeWire y paneles emergentes de gestion.

## 2. Contratos y API
- **DynamicIsland.qml**:
  - Propiedades obligatorias: `required property var bar`.
  - Estados: Modo reposo (reloj + calendario) y modo multimedia activo (caratula circular, titulo/artista, ecualizador animado, reloj compacto).
  - Interaccion:
    - Clic izquierdo sobre area multimedia: Despliega/contrae la isla dinamica expandida (`bar.toggle("media")`).
    - Clic izquierdo sobre reloj lateral: Despliega/contrae `CalendarPanel`.
    - Clic derecho: Conmuta alternativamente entre reproductor y calendario.
- **DynamicIslandExpanded.qml**:
  - Propiedades obligatorias: `required property var bar`, `property Item anchorItem`.
  - Morfismo espacial: Se expande desde la geometria de la isla compacta (220x24 px) hasta la tarjeta de reproduccion completa (420x180 px, radio de 36 px) sin alterar la geometria de ventanas en Hyprland (`ExclusionMode.Ignore`).
  - Caratula circular recortada mediante `MultiEffect` (QtQuick.Effects), titulo en negrita y artista subordinado.
  - Linea de tiempo interactiva (scrubber) con cabezal deslizante (thumb knob) y tiempos numericos transcurrido y restante.
  - Controles multimedia dedicados: Shuffle, Anterior, Boton central solido blanco circular con icono negro de Play/Pausa, Siguiente, Repetir.
  - Atmosfera adaptativa: Gradiente de resplandor ambiental inferior e iluminacion perimetral sincronizada reactivamente con la aplicacion activa (Spotify verde, Brave naranja, Firefox naranja-rojizo, etc.).
- **TasksButton.qml / TasksPanel.qml**:
  - Consumo de eventos Hyprland IPC mediante `Quickshell.Hyprland` (`Hyprland.toplevels.values`) con filtrado de superficies invalidas/auxiliares.
  - Despachadores IPC compatibles con Hyprland 0.57+ Lua (`hl.dsp.window.close` y `hl.dsp.focus`).

## 3. Dependencias
- `quickshell` (version >= 0.0.10) con modulos `Wayland`, `Hyprland`, `Services.Mpris`, `Services.Pipewire` e `Io`.
- `Qt6QuickEffects` (`QtQuick.Effects`) para mascaras de recorte geometrico circular en tiempo real.
- `hyprland` (version >= 0.57.0) con soporte de reglas de capa (`layer_rule`) y Lua IPC.
- D-Bus `org.mpris.MediaPlayer2` (Spotify, navegadores y reproductores multimedia locales).

## 4. Mapa de Archivos
- `bar/Bar.qml`: Ensamblador principal de la barra flotante transparente y distribuidor de anclajes.
- `bar/DynamicIsland.qml`: Isla dinamica interactiva central compacta con morfismo visual y animaciones reactivas.
- `bar/DynamicIslandExpanded.qml`: Reproductor de musica expandido de la Dynamic Island estilo iPhone con morfismo desde la barra superior.
- `bar/Capsule.qml`: Contenedor visual de capsula flotante con fondo redondeado `Theme.barSurface` y borde delimitador de 1 px.
- `bar/Workspaces.qml`: Selector de espacios de trabajo con indicador deslizante elastico y borde flotante.
- `bar/StatusButton.qml`: Componente atomico de boton con icono vectorial, etiqueta y tooltip.
- `bar/TasksButton.qml`: Contador y conmutador del gestor de aplicaciones en segundo plano.
- `panels/PopupPanel.qml`: Ventana overlay de tarjeta flotante con bordes redondeados y desenfoque `quickshell-panel`.
- `panels/MediaPanel.qml`: Panel legado de reproductor multimedia.
- `panels/CalendarPanel.qml`: Calendario interactivo mensual desplegable bajo la Isla Dinamica.
- `panels/TasksPanel.qml`: Panel gestor de ventanas abiertas con enfoque y terminacion de procesos.

## 5. Logica y Flujo
1. Quickshell inicializa `shell.qml` y crea una instancia de `Bar.qml` por cada pantalla detectada.
2. `Bar.qml` se registra con fondo 100% transparente en el namespace `quickshell-bar`, permitiendo que el papel tapiz se aprecie nitido entre las capsulas flotantes.
3. Las capsulas en los extremos (`leftGroup`, `rightGroup`) y la `DynamicIsland` en el centro flotan de forma independiente con un borde sutil de 1 px (`Theme.barFg`, 0.10).
4. `DynamicIsland` monitorea activamente el servicio MPRIS; cuando un reproductor pasa a estado `Playing`, la capsula se expande suavemente (curva Bezier [0.16, 1, 0.3, 1, 1, 1]), mostrando la caratula circular, el ecualizador animado y el titulo del tema.
5. Al hacer clic sobre la isla o invocar `bar.toggle("media")`, la isla compacta transiciona su opacidad a 0 mientras `DynamicIslandExpanded` despliega el reproductor completo desde el borde superior de la barra, animando anchura, altura y radio de curvatura.

## 6. Decisiones de Diseño y Gotchas
- **Morfismo integrado sin desplazar ventanas**: `DynamicIslandExpanded` se implementa en un `PanelWindow` overlay con `exclusionMode: ExclusionMode.Ignore` y `margins.top: -Theme.barHeight`, permitiendo que la tarjeta se extienda desde y=3 px directamente sobre la barra sin obligar a Hyprland a reacomodar ventanas en mosaico.
- **Caratulas circulares con MultiEffect**: En Qt Quick, la propiedad `clip: true` en un `Rectangle` unicamente recorta sobre el cuadro delimitador rectangular. Se incorporo `QtQuick.Effects` con `MultiEffect` y mascara de capa para renderizar carátulas estrictamente circulares tanto en modo compacto como expandido.
- **Resplandor ambiental adaptativo**: Se implemento una capa de gradiente vertical suave en la mitad inferior de la tarjeta que absorbe el color representativo del reproductor en ejecucion (Spotify `#1DB954`, Brave `#FF5500`, Firefox `#FF7139`, Chrome `#4285F4`, VLC `#FF8800`) sin formas geometricas cortadas ni artefactos visuales.
- **Fondo solido antirreflejo**: La tarjeta de la isla utiliza un fondo solido negro azabache (`#0a0b0e`), evitando que el texto o ventanas de fondo se trasluzcan o contaminen la interfaz.
- **Aceleracion de curva de animacion**: Se optimizo la duracion de expansion a 180ms y contraccion a 140ms bajo curva Bezier elastica `[0.1, 0.9, 0.2, 1.0]`, eliminando lentitud perceptible.
- **Glifo de pausa geometrico**: Se sustituyo el glifo tipografico de pausa (susceptible a interpretarse visualmente como '00') por dos barras rectangulares negras redondeadas de precision milimetrica.

## 7. Estado y Ultimos Cambios
- Refinamiento estetico integral segun la captura de referencia: fondo negro azabache 100% opaco, tipografia sans-serif moderna (`Noto Sans` / `Cantarell`) y scrubber horizontal unificado en una sola linea.
- Aceleracion de animaciones a 180ms para respuesta inmediata tipo iOS.
- Correccion del icono de pausa central con barras geometricas puras.
- Reemplazo del resplandor eliptico cortado por un gradiente de iluminacion ambiental difusa.

## 8. Como Verificar
1. Reiniciar Quickshell: `pkill qs && qs -d -p ~/.local/share/hyprsimple/default/quickshell`
2. Verificar carga de configuracion en logs: `tail -n 20 /run/user/1000/quickshell/by-id/*/log.qslog`
3. Probar reproduccion MPRIS con Spotify o navegador: `playerctl play`
4. Expandir/contraer isla mediante clic en la isla o IPC: `qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle media`
