-- Override the hyprsimple autostart commands. Anything you set here wins,
-- because this file is loaded after the defaults in
-- ~/.local/share/hyprsimple/default/hypr/autostart.lua

hl.on("hyprland.start", function()
  -- Bloqueo inmediato al iniciar sesion: presenta hyprlock con renderizado inmediato
  hl.exec_cmd("uwsm app -- hyprlock --immediate-render")
end)
