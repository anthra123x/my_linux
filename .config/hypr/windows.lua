-- Override the hyprsimple window rules. Anything you set here wins, because
-- this file is loaded after the defaults in
-- ~/.local/share/hyprsimple/default/hypr/windows.lua

-- Reglas para juegos y emuladores (latencia minima y tearing directo)
hl.window_rule({ match = { class = "^(steam_app_.*)$" }, immediate = true })
hl.window_rule({ match = { class = "^(gamescope)$" }, immediate = true })
hl.window_rule({ match = { title = ".*\\.exe" }, immediate = true })

-- Reglas para Quickshell (desenfoque liquid glass en la barra superior y menus desplegables)
hl.layer_rule({ match = { namespace = "quickshell" }, blur = true, ignore_alpha = 0.1 })
hl.layer_rule({ match = { namespace = "quickshell-panel" }, no_anim = true })

-- Regla para Kitty (opacidad administrada por Kitty con background_opacity y blur de fondo)
hl.window_rule({ match = { class = "^(kitty)$" }, opacity = "1.0 1.0" })


