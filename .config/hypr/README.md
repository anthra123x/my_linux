# Modulo: .config/hypr

Configuracion modular del compositor Wayland Hyprland para Omicron Shell.

---

## 1. Proposito y Alcance
Controlar la gestion de ventanas dinámicas en mosaico (tiling), composicion grafica acelerada por hardware (Intel VA-API / Aquamarine), configuracion de monitores, animaciones a 60 FPS sin tirones y atajos de teclado globales del sistema.

---

## 2. Contratos
- **Entrada:** Configuracion declarativa en Lua cargada por Hyprland (`hyprland.lua`).
- **Salida / Control:** Socket IPC UNIX en `/run/user/$UID/hypr/` (`.socket.sock` para consultas JSON y `.socket2.sock` para eventos de ventanas y espacios de trabajo).
- **Invariantes visuales:** Tasa de refresco a 60 FPS consistentes (`misc.render_unfocused_fps = 60`), renderizado dinamico con `new_render_scheduling = true` y curvas `snappy` para cambios inmediatos.

---

## 3. Dependencias
- **Binarios del sistema:** `Hyprland` (0.57+), `hypridle`, `hyprlock`, `hyprsunset`, `xdg-desktop-portal-hyprland`.
- **Modulos auxiliares:** Quickshell (barra y widgets), `wallmotion` (fondos animados), `fuzzel` (lanzador).

---

## 4. Mapa de Archivos
- `hyprland.lua`: Punto de entrada principal que carga los submódulos.
- `looknfeel.lua`: Estetica visual, animaciones bezier, bordes, opacidad y parametros del motor de render.
- `monitors.lua`: Resolucion, tasa de refresco (60 Hz) y disposicion de pantallas.
- `input.lua`: Distribucion de teclado, touchpad, aceleracion y sensibilidad de puntero.
- `autostart.lua`: Comandos y servicios de arranque de sesion grafica.
- `vars.lua`: Variables de entorno y aplicaciones predeterminadas (terminal, navegador, editor).
- `windows.lua`: Reglas de posicionamiento, flotacion y opacidad por clase de ventana.
- `bindings/applications.lua`: Atajos de teclado para lanzamiento de aplicaciones y control de sesion.
- `shaders/`: Shaders GLSL de post-procesado visual opcional (`oled.glsl`, `idle-blur.glsl`).

---

## 5. Decisiones y Gotchas
1. **Configuracion en Lua vs Hyprlang:** El sistema utiliza la API en Lua de Hyprland para permitir composicion programatica de reglas, consultas del entorno del usuario e importacion modular sin archivos monoliticos.
2. **Direct Scanout Desactivado:** `direct_scanout = 0` se mantiene para evitar colisiones de tearing y parpadeos cuando la barra flotante de Quickshell o las notificaciones se superponen sobre ventanas a pantalla completa.

---

## 6. Como Verificar
```bash
# Comprobar sintaxis y estado del compositor
hyprctl reload
hyprctl monitors -j
hyprctl getoption misc:render_unfocused_fps
```
