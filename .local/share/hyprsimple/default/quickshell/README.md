# Quickshell UI (Omicron Shell)

## 1. Proposito y Alcance
Provee la suite de interfaz de usuario de escritorio en Wayland mediante Quickshell para Hyprland. Incluye la barra superior de estado con capsulas flotantes independientes sin fondo solido ni desenfoque transversal, la isla dinamica central (Dynamic Island) con reproductor de musica expandible al estilo iOS, selector de areas de trabajo, monitores de recursos del sistema, controles de audio PipeWire y paneles emergentes de gestion.

## 2. Contratos y API
- **DynamicIsland.qml**:
  - Propiedades obligatorias: `required property var bar`.
  - Estados:
    - Modo reposo: Capsula solida negra azabache (`#000000`) con badge Apple de calendario (encabezado rojo y dia), fecha y hora digital nitida.
    - Modo multimedia: Caratula circular con mascara MultiEffect, metadatos de pista sans-serif, ecualizador reactivo animado y reloj compacto.
  - Interaccion:
    - Clic izquierdo sobre area multimedia: Despliega/contrae el reproductor expandido de la isla dinamica (`bar.toggle("media")`).
    - Clic izquierdo en reposo (o sobre reloj compacto): Despliega/contrae el calendario Apple integrado en la isla dinamica (`bar.toggle("calendar")`).
    - Clic derecho: Conmuta alternativamente entre reproductor y calendario sin cerrar la isla.
- **DynamicIslandExpanded.qml**:
  - Propiedades obligatorias: `required property var bar`, `property Item anchorItem`.
  - Contenedor unificado: Soporta modo multimedia (`bar.openPanel === "media"`, 400x165 px, radio 36 px) y modo calendario (`bar.openPanel === "calendar"`, 330x288 px, radio 32 px).
  - Morfismo espacial: Se expande desde la geometria de la isla compacta (ancho y alto del anclaje, radio de capsula `height / 2`) hasta la tarjeta final mediante fisica Apple Fluid de 6 puntos (`[0.16, 1, 0.3, 1, 1, 1]`).
  - Cross-fade interno: Capa compacta intermedia que se desvanece suavemente en el primer tercio de la expansion, dando paso a los controles expandidos con escala y opacidad progresivas sin recortes de elementos.
  - Reproductor multimedia: Caratula circular, titulo, artista, scrubber interactivo en una sola fila, boton Play/Pausa hero blanco con barras de pausa geometricas e iluminacion ambiental difusa adaptativa a la caratula.
  - Calendario Apple integrado: Cabecera con fecha en rojo Apple (`#ff3b30`), mes y año con botones circulares de navegacion, fila de dias y cuadricula `MonthGrid` con indicador circular de dia actual y soporte para rueda de raton.
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
- **Morfismo unificado y supresion de popups desvinculados**: El calendario ya no se despliega como una ventana emergente rectangular separada bajo la barra. Se integro directamente en `DynamicIslandExpanded`, permitiendo que la propia isla dinamica se expanda fisicamente hacia abajo tanto en modo multimedia como en modo calendario, preservando la continuidad de la capsula central.
- **Correccion de curvas Bezier de 6 puntos en Qt Quick**: La propiedad `easing.bezierCurve` para `Easing.BezierSpline` exige estrictamente un arreglo de 6 valores (`[c1x, c1y, c2x, c2y, 1, 1]`). La falta de los ultimos dos valores impedia que la interpolacion completara el recorrido, ocasionando interrupciones abruptas en el despliegue.
- **Cross-fade interno multinivel**: Para erradicar cualquier parpadeo o visualizacion prematura de controles recortados a mitad de despliegue, el contenedor morfico presenta una capa intermedia compacta que se desvanece en los primeros 70 ms, mientras la vista expandida (reproductor o calendario) escala suavemente desde 0.94 hasta 1.0 con ganancia progresiva de opacidad.
- **Resplandor ambiental adaptativo segun la caratula**: Implementacion del script `dynamic-island-color.py` que analiza la paleta de la caratula de la pista activa en espacio HSL para extraer el tono vibrante dominante (con cache de respuesta instantanea en memoria/disco). Se aplica mediante foco desenfocado con `MultiEffect` (`blur: 1.0`, `blurMax: 32`) y gradiente vertical restringido estrictamente al `radius` del contenedor, eliminando cualquier fuga o corte rectangular en las esquinas.
- **Estetica Apple en modo reposo**: Se erradico el fondo gris generico y el icono de calendario purpura antiguo. La isla en reposo adopta un cuerpo solido negro azabache (`#000000`), mini-badge Apple de calendario con franja roja y numero de dia, tipografia sans-serif calibrada y reloj digital en blanco puro.

## 7. Estado y Ultimos Cambios
- Rediseño integral de la Isla Dinamica en modo reposo: estilo de hardware Apple en negro azabache solido, mini-badge de calendario y hora digital de alta precision.
- Unificacion del calendario mensual interactivo dentro del contenedor morfico de la Isla Dinamica, eliminando la ventana flotante desvinculada `CalendarPanel`.
- Correccion de la fisica de interpolacion BezierSpline a 6 puntos (`[0.16, 1, 0.3, 1, 1, 1]` y `[0.38, 0.0, 0.20, 1.0, 1, 1]`) garantizando un despliegue y repliegue 100% fluido.
- Validacion visual y funcional de la transicion entre reposo, reproduccion activa en Spotify, despliegue de reproductor y despliegue de calendario.

## 8. Como Verificar
1. Reiniciar Quickshell: `pkill qs && qs -d -p ~/.local/share/hyprsimple/default/quickshell`
2. Verificar carga de configuracion en logs: `tail -n 20 /run/user/1000/quickshell/by-id/*/log.qslog`
3. Probar reproduccion MPRIS con Spotify o navegador: `playerctl play`
4. Expandir/contraer isla mediante clic en la isla o IPC: `qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle media`
