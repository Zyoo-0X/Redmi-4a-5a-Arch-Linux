# Autologin tty1 -> KDE Plasma Wayland (tanpa SDDM, jimat RAM)
[ -f ~/.bashrc ] && . ~/.bashrc
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true
  export KWIN_IM_SHOW_ALWAYS=1
  if [ -x /usr/lib/plasma-dbus-run-session-if-needed ]; then
    exec /usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland
  fi
  exec dbus-run-session /usr/bin/startplasma-wayland
fi
