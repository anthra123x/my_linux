-- Your monitor layout. hyprsimple copies this file once and never touches it
-- again, so anything you set here stays set.

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and resolutions: hyprctl monitors all

-- Monitor principal (pantalla integrada fijada a 1920x1080@60Hz)
hl.env("GDK_SCALE", "1")
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1, vrr = 0 })

-- Monitor externo (HDMI-A-1 como extension a 1920x1080@100Hz)
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@100", position = "auto", scale = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })


-- Optimized for retina-class 2x displays (13" 2.8K, 27" 5K, 32" 6K):
-- hl.env("GDK_SCALE", "2")
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- 27"/32" 4K fractional compromise:
-- hl.env("GDK_SCALE", "1.75")
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })

-- Framework 13 + 6K XDR Apple display:
-- hl.monitor({ output = "DP-5", mode = "6016x3384@60", position = "auto", scale = 2 })
-- hl.monitor({ output = "eDP-1", mode = "2880x1920@120", position = "auto", scale = 2 })
