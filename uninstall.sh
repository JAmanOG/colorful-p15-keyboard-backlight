#!/usr/bin/env bash
# uninstall.sh — remove the kbdlight tool (leaves the tuxedo_keyboard driver in place).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo ./uninstall.sh"; exit 1; }

systemctl disable --now kbdlight-keys.service    >/dev/null 2>&1 || true
systemctl disable kbdlight-restore.service       >/dev/null 2>&1 || true
rm -f /usr/local/bin/kbdlight /usr/local/bin/kbdlight-gui /usr/local/bin/kbdlight-listen \
      /usr/share/applications/kbdlight.desktop \
      /etc/udev/rules.d/99-kbdlight.rules \
      /etc/systemd/system/kbdlight-restore.service \
      /etc/systemd/system/kbdlight-keys.service \
      /usr/lib/systemd/system-sleep/kbdlight-resume
systemctl daemon-reload || true
udevadm control --reload-rules || true
# restore the desktop's built-in keyboard-backlight key bindings
if [ -n "${SUDO_USER:-}" ] && command -v gsettings >/dev/null 2>&1; then
    uid="$(id -u "$SUDO_USER")"
    for k in keyboard-brightness-up-static keyboard-brightness-down-static keyboard-brightness-toggle-static; do
        sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            gsettings reset org.gnome.settings-daemon.plugins.media-keys "$k" 2>/dev/null || true
    done
fi
echo "Removed kbdlight. (Kept: tuxedo driver, /etc/modprobe.d/tuxedo-kbd.conf, /var/lib/kbdlight.)"
echo "To remove state too:  rm -rf /var/lib/kbdlight"
