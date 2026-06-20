#!/usr/bin/env bash
#
# install.sh — install the kbdlight tool, udev rule and boot/resume restore.
# Run with sudo:  sudo ./install.sh
#
# Assumes the tuxedo_keyboard driver is already installed via DKMS (see README).
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo ./install.sh"; exit 1; }

# group that gets passwordless access to the LED (the desktop user is in it)
GRP="${KBDLIGHT_GROUP:-users}"
LED=/sys/class/leds/rgb:kbd_backlight

if [ ! -e "$LED/brightness" ]; then
    echo "WARNING: $LED not found — the driver isn't set up yet."
    echo "         Run  sudo ./install-driver.sh  first, then re-run this. Continuing anyway..."
fi

echo "==> binaries"
install -m 0755 "$HERE/kbdlight"        /usr/local/bin/kbdlight
install -m 0755 "$HERE/kbdlight-gui.py" /usr/local/bin/kbdlight-gui

echo "==> desktop entry"
install -m 0644 "$HERE/data/kbdlight.desktop" /usr/share/applications/kbdlight.desktop

echo "==> udev rule (passwordless access for group '$GRP')"
sed "s/\busers\b/$GRP/" "$HERE/data/99-kbdlight.rules" > /etc/udev/rules.d/99-kbdlight.rules
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=leds || true
# apply now too (no 'add' event fires for an already-present node)
if [ -e "$LED/brightness" ]; then
    chgrp "$GRP" "$LED/brightness" "$LED/multi_intensity" 2>/dev/null || true
    chmod 0664   "$LED/brightness" "$LED/multi_intensity" 2>/dev/null || true
fi

echo "==> state dir + default"
install -d -m 0775 -g "$GRP" /var/lib/kbdlight
if [ ! -f /var/lib/kbdlight/state ]; then
    printf 'brightness=153\nintensity="255 255 255"\n' > /var/lib/kbdlight/state
fi
chgrp "$GRP" /var/lib/kbdlight/state; chmod 0664 /var/lib/kbdlight/state

echo "==> boot + resume restore"
install -m 0644 "$HERE/data/kbdlight-restore.service" /etc/systemd/system/kbdlight-restore.service
install -m 0755 "$HERE/data/kbdlight-resume"          /usr/lib/systemd/system-sleep/kbdlight-resume
systemctl daemon-reload
systemctl enable kbdlight-restore.service >/dev/null 2>&1 || true

echo
echo "Done. Try:  kbdlight color red   |   kbdlight set 60   |   kbdlight-gui"
if [ ! -e "$LED/brightness" ]; then
    echo "NOTE: $LED not present yet — load the driver (sudo modprobe clevo_acpi clevo_wmi) or reboot."
fi
