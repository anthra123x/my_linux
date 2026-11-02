-- Override the hyprsimple look and feel.
-- Sleek minimalist aesthetic with smooth 60fps performance on Intel UHD Graphics
-- and OLED emulation shader for deep contrast and vibrant colors.

local home = os.getenv("HOME") or ""

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 0,
    resize_on_border = true,
    allow_tearing = true,
  },
  render = {
    direct_scanout = 0, -- Desactivado para evitar micro-tirones al superponer la barra Quickshell y popups
    new_render_scheduling = true, -- Triple buffering dinamico en iGPU bajo carga para evitar caidas de 60 FPS
  },
  decoration = {
    rounding = 10,
    active_opacity = 1.0,
    inactive_opacity = 1.0, -- Opacidad completa para evitar sobrecarga de composicion en segundo plano
    -- screen_shader = home .. "/.config/hypr/shaders/oled.glsl", -- Desactivado para eliminar latencia de post-procesado en cada frame
    shadow = {
      enabled = false,
    },
    blur = {
      enabled = true,
      size = 3,
      passes = 1, -- 1 pasada ultraligera para Intel UHD
      new_optimizations = true,
      ignore_opacity = true, -- Evita recalcular blur en elementos con opacidad
      vibrancy = 0.15,
    },
  },
  misc = {
    vrr = 0, -- Tasa fija a 60Hz sin fluctuaciones de refresco
    render_unfocused_fps = 30, -- 30 FPS en segundo plano para ahorrar ancho de banda y priorizar 60 FPS limpios en la app activa
  },
})

-- Curvas bezier y animaciones fluidas calibradas a 60Hz (inmediatas y sin overshoot lento)
hl.curve("fluid60", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("snappy", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "snappy", style = "popin 80%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "snappy", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "snappy", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "snappy" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "fluid60" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "fluid60", style = "slide" })

