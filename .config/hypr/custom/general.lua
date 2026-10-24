-- Local hardware settings for this CachyOS laptop.
-- Keep these in custom/ so upstream updates can replace the main config safely.

-- Current panel: Chimei Innolux 1920x1080 at 60 Hz, native scale.
--
-- El panel declara 1920x1080@60 y 1920x1080@48 en su EDID. Se fija 60Hz
-- explicito para que Hyprland nunca elija solo el modo de 48Hz (ahorra energia
-- cuando cree que la pantalla esta "inactiva" y luego vuelve a 60 con un
-- parpadeo). El limite del panel es 60Hz: no hay mas rates disponibles.
hl.monitor({
    output = "eDP-1",
    mode = "1920x1080@60",
    position = "0x0",
    scale = 1.0,
})

-- Monitor externo: DHI LM22-A200Y (22", 1920x1080 nativo) por HDMI.
--
-- El EDID de este monitor anuncia 1920x1080@75Hz y 1920x1080@100Hz (pixel
-- clock 228.66 MHz), y declara "Max TMDS clock 360 MHz". Pero el driver i915
-- de este Alder Lake-N RECHAZA cualquier modo por encima de ~166 MHz de pixel
-- clock, asi que ni 75Hz ni 100Hz llegan nunca a exponerse en availableModes.
-- Medido empiricamente: el techo real es 166 MHz (165.376 entra, 166.333 no).
--
-- Con ese techo, 100Hz en 1080p es imposible: haria falta un reloj de
-- 208.9 MHz como minimo. El maximo alcanzable es ~76Hz, y a 75Hz el reloj
-- baja a 165 MHz si usamos timings de blanking reducido (CVT-RB v2):
--
--   165.000 MHz / (2000 htotal * 1100 vtotal) = 75.000 Hz exacto
--
-- Se usa el modeline en vez de "1920x1080@75" a proposito: ese modo existe en
-- el EDID solo con blanking estandar (175.5 MHz), que el driver rechaza. El
-- modeline de abajo es la unica forma de llegar a 75Hz con este techo.
hl.monitor({
    output = "HDMI-A-1",
    mode = "modeline 165.000 1920 1936 1968 2000 1080 1083 1088 1100 +hsync +vsync",
    position = "1920x0",
    scale = 1.0,
})

-- Preserve the working local input behavior.
hl.config({
    input = {
        kb_layout = "us",
        accel_profile = "flat",
    },
})

-- Estilo Windows 11 para las ventanas.
--
-- Va en custom/ y no en hyprland/general.lua porque este se regenera con
-- dotfiles-update; ademas colors.lua lo produce matugen y se sobreescribe solo.
--
-- Que cambia respecto a la config de upstream:
--
--   rounding 18 -> 8
--       Windows 11 usa 8 px de radio exacto. Con 18 las ventanas se ven
--       muy redondeadas, mas estilo GNOME/macOS que Win11.
--
--   rounding_power 2.5 -> 2.0
--       Bajarlo convierte el squircle exagerado en un rectángulo redondeado
--       normal, que es lo que dibuja Windows.
--
--   shadow.enabled false -> true
--       Win11 siempre proyecta una sombra suave bajo las ventanas. Este es de
--       los cambios que mas se notan al estilo.
--
--   blur.size 10 -> 14
--       Mas difuminado, que es el acrylic de Win11. passes se queda en 1 a
--       proposito: en una iGPU (Intel UHD del i3-N305) cada pasada extra de
--       blur se paga en GPU, y el equipo ya va justo de RAM.
--
-- Este bloque se carga DESPUES de hyprland/general.lua, asi que gana.
hl.config({
    decoration = {
        rounding = 8,
        rounding_power = 2.0,
        shadow = {
            enabled = true,
            range = 24,
            offset = { 0, 3 },
            render_power = 3,
            color = "rgba(00000033)",
        },
        blur = {
            size = 14,
            passes = 1,
        },
    },
})
