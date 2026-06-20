#!/usr/bin/env bash
# uninstall.sh — remove the kbdlight tool (leaves the tuxedo_keyboard driver in place).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo ./uninstall.sh"; exit 1; }

systemctl disable kbdlight-restore.service >/dev/null 2>&1 || true
rm -f /usr/local/bin/kbdlight /usr/local/bin/kbdlight-gui \
      /usr/share/applications/kbdlight.desktop \
      /etc/udev/rules.d/99-kbdlight.rules \
      /etc/systemd/system/kbdlight-restore.service \
      /usr/lib/systemd/system-sleep/kbdlight-resume
systemctl daemon-reload || true
udevadm control --reload-rules || true
echo "Removed kbdlight. (Kept: tuxedo driver, /etc/modprobe.d/tuxedo-kbd.conf, /var/lib/kbdlight.)"
echo "To remove state too:  rm -rf /var/lib/kbdlight"
