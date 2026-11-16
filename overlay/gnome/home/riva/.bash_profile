# Autologin tty1 -> GNOME Wayland (tanpa GDM, jimat RAM)
[ -f ~/.bashrc ] && . ~/.bashrc
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome
  exec dbus-run-session -- gnome-session
fi
