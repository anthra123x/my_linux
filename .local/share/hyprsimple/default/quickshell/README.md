# Modulo Quickshell UI (Omicron Shell)

## 1. Proposito y Alcance
Provee la suite de interfaz de usuario de escritorio en Wayland mediante Quickshell, implementando la barra superior de capsulas flotantes independientes (sin fondo solido ni desenfoque de banda), la Isla Dinamica central (Dynamic Island) con reproductor MPRIS integrado y reloj sincronizado, el gestor de aplicaciones en segundo plano de Hyprland y las ventanas emergentes translúcidas de control del sistema.

## 2. Contratos y API
- **Bar.qml**:
  - `openPanel`: string (identificador de panel activo: "media", "calendar", "tasks", "volume", "system", etc.).
  - `toggle(name: string)`: abre o contrae el panel correspondiente.
  - `WlrLayershell.namespace = "quickshell-bar"` con `color = "transparent"`.
- **DynamicIsland.qml**:
  - Morfismo automatico segun estado MPRIS:
    - Estado reposo: Fecha completa y hora sincronizada con icono de calendario.
    - Estado reproduciendo: Caratula miniatura de 16x16 px, ecualizador animado de 4 barras reactivas, texto artista-pista (truncado a 26 caracteres) y reloj lateral compacto.
  - Interaccion:
    - Clic izquierdo sobre area multimedia: Despliega/contrae `MediaPanel` centrado directamente bajo la isla.
    - Clic izquierdo sobre reloj lateral: Despliega/contrae `CalendarPanel`.
    - Clic derecho: Conmuta alternativamente entre `MediaPanel` y `CalendarPanel`.
- **MediaPanel.qml**:
  - Consumo de D-Bus MPRIS mediante `Quickshell.Services.Mpris` (`Mpris.players.values`).
  - Deteccion automatica de reproductor en reproduccion (`playbackState === MprisPlaybackState.Playing`) con soporte multitab.
  - Metodos y controles: `togglePlaying()`, `next()`, `previous()`, ajuste de volumen y posicionamiento en pista.
- **TasksButton.qml / TasksPanel.qml**:
  - Consumo de eventos Hyprland IPC mediante `Quickshell.Hyprland` (`Hyprland.toplevels.values`) con filtrado de superficies invalidas/auxiliares.
  - Despachadores IPC compatibles con Hyprland 0.57+ Lua (`hl.dsp.window.close` y `hl.dsp.focus`).

## 3. Dependencias
- `quickshell` (version >= 0.0.10) con modulos `Wayland`, `Hyprland`, `Services.Mpris`, `Services.Pipewire` e `Io`.
- `hyprland` (version >= 0.57.0) con soporte de reglas de capa (`layer_rule`) y Lua IPC.
- D-Bus `org.mpris.MediaPlayer2` (Spotify, navegadores y reproductores multimedia locales).

## 4. Mapa de Archivos
- `bar/Bar.qml`: Ensamblador principal de la barra flotante transparente y distribuidor de anclajes.
- `bar/DynamicIsland.qml`: Isla dinamica interactiva central tipo macOS con morfismo visual y animaciones reactivas.
- `bar/Capsule.qml`: Contenedor visual de capsula flotante con fondo redondeado `Theme.barSurface` y borde delimitador de 1 px.
- `bar/Workspaces.qml`: Selector de espacios de trabajo con indicador deslizante elastico y borde flotante.
- `bar/StatusButton.qml`: Componente atomico de boton con icono vectorial, etiqueta y tooltip.
- `bar/TasksButton.qml`: Contador y conmutador del gestor de aplicaciones en segundo plano.
- `panels/PopupPanel.qml`: Ventana overlay de tarjeta flotante con bordes redondeados y desenfoque `quickshell-panel`.
- `panels/MediaPanel.qml`: Panel extendido del reproductor multimedia con caratula, carrusel de fuentes, slider de posicion y volumen.
- `panels/CalendarPanel.qml`: Calendario interactivo mensual desplegable bajo la Isla Dinamica.
- `panels/TasksPanel.qml`: Panel gestor de ventanas abiertas con enfoque y terminacion de procesos.

## 5. Logica y Flujo
1. Quickshell inicializa `shell.qml` y crea una instancia de `Bar.qml` por cada pantalla detectada.
2. `Bar.qml` se registra con fondo 100% transparente en el namespace `quickshell-bar`, permitiendo que el papel tapiz se aprecie nitido entre las capsulas flotantes.
3. Las capsulas en los extremos (`leftGroup`, `rightGroup`) y la `DynamicIsland` en el centro flotan de forma independiente con un borde sutil de 1 px (`Theme.barFg`, 0.10).
4. `DynamicIsland` monitorea activamente el servicio MPRIS; cuando un reproductor pasa a estado `Playing`, la capsula se expande suavemente (curva Bezier [0.16, 1, 0.3, 1, 1, 1]), mostrando la caratula, el ecualizador animado y el titulo del tema.
5. Al hacer clic sobre la isla, esta invoca `bar.toggle("media")`, desplegando el `MediaPanel` como una extension vertical que desciende directamente desde el centro de la isla.

## 6. Decisiones de Diseño y Gotchas
- **Eliminacion del desenfoque de barra**: Se elimino `color: Qt.alpha(Theme.barBg, 0.70)` de `Bar.qml` y se desacoplo el namespace a `quickshell-bar`. En `.config/hypr/windows.lua`, la regla de desenfoque aplica exclusivamente a `quickshell-panel`, garantizando que la barra no genere bandas de desenfoque sobre el fondo.
- **Tarjetas flotantes sin alas en PopupPanel**: Se reemplazo la forma con alas de anclaje plano (`flare`) por un contorno de tarjeta flotante con radio de 14 px y margen superior de `Theme.barHeight + 4`, armonizando con la estetica flotante.
- **Prioridad dinamica en MPRIS**: `selectedIndex` en `MediaPanel` se inicializa en `-1` para priorizar de manera reactiva cualquier aplicacion que comience a reproducir audio, evitando quedar fijado en pestañas inactivas de navegadores.

## 7. Estado y Ultimos Cambios
- Rediseño integral de la barra de tareas: retirada de fondo solido y desenfoque global, estetica de capsulas flotantes.
- Remocion del reproductor independiente lateral e implementacion de `DynamicIsland.qml` en el centro de la barra.
- Reenrutamiento de todos los paneles centrales (`media`, `calendar`, `clipboard`, `wallpapers`, `record`, `keybinds`) anclandose a la Isla Dinamica.
- Actualizacion de reglas de capa en Hyprland para soporte hermetico de `quickshell-panel` vs `quickshell-bar`.

## 8. Como Verificar
- Validar ejecucion del proceso Quickshell: `pgrep -x qs`
- Inspeccionar capas Wayland activas: `hyprctl layers | grep quickshell`
- Verificar conmutacion de la Isla Dinamica:
  - Desplegar reproductor extendido: `qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle media`
  - Desplegar calendario: `qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle calendar`
