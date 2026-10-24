-- Variables de entorno de la sesion Hyprland.
-- Este archivo se carga desde custom/env.lua, que se incluye al final de la
-- configuracion, asi que lo de aqui gana.

-- Keep X11 and Wayland applications on the same cursor theme.
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")

-- Memoria: el motor QML de Quickshell guarda en disco una copia del bytecode
-- de cada componente .qml. Eso son ~35 MiB de RSS resident que solo sirve
-- para arrancar mas rapido la proxima vez. En una maquina de 8 GB donde la RAM
-- es el recurso escaso, conviene priorizar memoria sobre un arranque
-- marginally mas rapido.
hl.env("QML_DISABLE_DISK_CACHE", "1")
