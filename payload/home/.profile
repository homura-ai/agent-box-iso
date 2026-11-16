# Start sway when logging in on the first console.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then exec sway; fi
