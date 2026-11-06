# Modulo Quickshell UI (Omicron Shell)

## 1. Proposito y Alcance
Provee la suite de interfaz de usuario de escritorio en Wayland mediante Quickshell, implementando la barra superior de capsulas flotantes, el mini reproductor multimedia con controles MPRIS y el gestor de aplicaciones en segundo plano y toplevels de Hyprland.

## 2. Contratos
- Bar.qml:
  - openPanel: string (identificador de panel activo: "media", "tasks", "volume", "system", etc.).
  - toggle(name: string): abre o contrae el panel correspondiente.
- MediaButton.qml / MediaPanel.qml:
  - Consumo de D-Bus MPRIS mediante Quickshell.Services.Mpris (Mpris.players.values).
  - Senales y metodos: togglePlaying(), next(), previous(), volume.
  - Propiedades: trackTitle, trackArtist, trackArtUrl, playbackState, position, length.
- TasksButton.qml / TasksPanel.qml:
  - Consumo de eventos Hyprland IPC mediante Quickshell.Hyprland (Hyprland.toplevels.values) con filtrado de superficies invalidas/auxiliares.
  - Despachadores IPC compatibles con Hyprland 0.57+ Lua (hl.dsp.window.close y hl.dsp.focus) con fallback clasico y control Wayland nativo.
  - Funcion: closeInactive() para depuracion quirurgica de ventanas secundarias.
  - Renderizado resiliente de iconos de aplicacion con fallback a simbolos vectoriales en caso de texturas no cargadas.

## 3. Dependencias
- quickshell (>= 0.0.10)
- hyprland (>= 0.57.0)
- PipeWire / WirePlumber (audio y sinks)
- D-Bus org.mpris.MediaPlayer2 (Spotify, navegadores y reproductores multimedia)

## 4. Mapa de Archivos
- bar/Bar.qml -> Ensamblador principal de la barra superior y registro de paneles.
- bar/Capsule.qml -> Contenedor visual de capsula con fondo redondeado Theme.barSurface.
- bar/StatusButton.qml -> Componente atomico de boton con icono, label y tooltip.
- bar/MediaButton.qml -> Indicador y conmutador del mini reproductor multimedia.
- bar/TasksButton.qml -> Contador y conmutador del gestor de aplicaciones en segundo plano.
- notifications/NotificationCard.qml -> Tarjeta de notificacion con carga asincrona segura y fallback vectorial.
- notifications/Notifications.qml -> Servicio y almacenamiento de notificaciones activas e historicas.
- panels/PopupPanel.qml -> Ventana overlay con animacion de resorte, blur y mascara de clic exterior.
- panels/MediaPanel.qml -> Panel de control multimedia con caratula, barra de progreso y volumen.
- panels/TasksPanel.qml -> Panel gestor de ventanas abiertas con enfoque y cierre quirurgico.

## 5. Decisiones y Gotchas
- Mpris.players es un UntypedObjectModel asincrono; se debe acceder a traves de Mpris.players.values.
- En MprisPlayer el metodo de conmutacion es togglePlaying() y no playPause().
- En Hyprland 0.57+ con configuracion en Lua, Hyprland.dispatch evalua expresiones Lua (hl.dsp.window.close y hl.dsp.focus) en lugar de cadenas planas de socket antiguo.
- Las superficies sin workspace asignado o ventanas auxiliares de IME (Default IME, SteamVR Status) se descartan del modelo visible para reflejar unicamente aplicaciones reales.
- Las imagenes de iconos de aplicacion ocultan el elemento Image hasta que status === Image.Ready, evitando el patron de textura ausente (checkerboard) de Qt Quick ante fallos de tema o iconos inexistentes.
- PopupPanel realiza un anclaje automatico centrado bajo el boton disparador, limitando la posicion a los bordes de la pantalla (edge clamp).
- Animacion de cierre unificada mediante Theme.closeAnim (270ms) y Theme.closeCurve ([0.38, 0.0, 0.20, 1.0, 1, 1]) con desvanecimiento no lineal de opacidad para una retraccion suave y amortiguada.

## 6. Como Verificar
- Validacion de sintaxis QML:
  timeout 3 quickshell -p ~/.local/share/hyprsimple/default/quickshell/shell.qml
- Reinicio de la barra en caliente:
  hyprsimple-restart-bar.sh
- Prueba de despliegue via IPC:
  qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle media
  qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle tasks


