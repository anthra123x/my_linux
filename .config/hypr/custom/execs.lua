-- Exec-once propios del usuario.
--
-- Este archivo se carga al final de la configuracion (desde custom/, que la
-- dotfile incluye despues de hyprland/), asi que lo de aqui corre una vez por
-- cada inicio de sesion de Hyprland.

-- Session restore: relanza las ventanas que estaban abiertas al cerrar la
-- sesion anterior.
--
-- El estado lo escribe ~/.local/bin/hypr-session-save, que corre cada 30 s
-- desde el timer de usuario hypr-session-save.timer. Se guarda en cada
-- intervalo y no solo al cerrar sesion a proposito: asi, si la maquina se
-- apaga de golpe o se cuelga, el ultimo estado guardado sigue siendo valido.
--
-- Va en background con la salida a un log porque la funcion arranca durante
-- el startup y no debe bloquear ni ensuciar la salida de Hyprland.
hl.exec_cmd("~/.local/bin/hypr-session-restore > /tmp/hypr-session-restore.log 2>&1 &")

-- lidwatch: al cerrar la tapa con un monitor externo conectado, deja el monitor
-- como salida principal (mueve ahi los escritorios y el foco).
--
-- Hyprland 0.56 elimino todo el soporte de tapa: no existe misc.lid_switch,
-- `hyprctl output <x> disable` es no-op y hl.dsp.dpms no baja el backlight. Por
-- eso el comportamiento lo implementa este script, acompanado de
-- /etc/systemd/logind.conf.d/50-lid.conf para que logind no suspenda al cerrar.
--
-- Arranca por systemd --user y no en background a pelo: asi el proceso queda
-- ligado a graphical-session.target y systemd lo reinicia si se cae.
hl.exec_cmd("systemctl --user start lidwatch.service >/dev/null 2>&1 &")
