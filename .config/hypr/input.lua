-- Override the hyprsimple input settings. Anything you set here wins.

hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      tap_to_click = true,
      clickfinger_behavior = true, -- 1 dedo: click izq, 2 dedos: click der, 3 dedos: click central
      disable_while_typing = true, -- Evita toques accidentales al escribir
      scroll_factor = 1.0,
    },
  },
  gestures = {
    workspace_swipe_distance = 300,
    workspace_swipe_cancel_ratio = 0.2, -- Con solo 20% de arrastre se confirma el cambio
    workspace_swipe_min_speed_to_force = 15, -- Flick rápido cambia de workspace instantáneamente
    workspace_swipe_direction_lock = true,
    workspace_swipe_direction_lock_threshold = 10,
    workspace_swipe_create_new = true, -- Crea un nuevo workspace si te pasas del último
    workspace_swipe_forever = true, -- Permite deslizar varios workspaces de corrido
  },
})

-- Gestos táctiles de 3 dedos
-- Deslizar horizontalmente con 3 dedos para cambiar de workspace de forma fluida
hl.gesture({
  fingers = 3,
  direction = "horizontal",
  action = "workspace",
})

-- Deslizar verticalmente con 3 dedos para alternar el workspace especial (scratchpad)
hl.gesture({
  fingers = 3,
  direction = "vertical",
  action = "special",
})

-- Soporte adicional de 4 dedos para compatibilidad
hl.gesture({
  fingers = 4,
  direction = "horizontal",
  action = "workspace",
})
hl.gesture({
  fingers = 4,
  direction = "vertical",
  action = "special",
})

