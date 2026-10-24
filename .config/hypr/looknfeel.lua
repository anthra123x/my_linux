-- Override the hyprsimple look and feel.
-- Sleek minimalist aesthetic with smooth 60fps performance on Intel UHD Graphics.

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 1,
    resize_on_border = true,
  },
  decoration = {
    rounding = 10,
    active_opacity = 1.0,
    inactive_opacity = 0.92,
    shadow = {
      enabled = false,
    },
    blur = {
      enabled = true,
      size = 6,
      passes = 2,
      new_optimizations = true,
      vibrancy = 0.15,
    },
  },
})
