#!/usr/bin/env bash
#
# install-driver.sh — build & install the patched tuxedo_keyboard driver that
# makes the keyboard backlight work on COLORFUL P15 23 and similar Tongfang/Clevo
# laptops whose firmware reports an *unrecognized* backlight type.
#
#   sudo ./install-driver.sh                 # auto: force 1-zone RGB only if needed
#   sudo FORCE_TYPE=2 ./install-driver.sh    # force a specific type (2=3-zone, 6=1-zone, 243=per-key)
#   sudo FORCE_TYPE=auto ./install-driver.sh # never force (rely on firmware detection)
#
# Installs via DKMS, so it survives kernel updates.
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo ./install-driver.sh"; exit 1; }

REPO="https://gitlab.com/commown/tuxedo-drivers"
PIN="4e1fb3a8897708676ba76603f15e20ce7e9ad5fe"   # commit this patch + dkms layout match
PATCH="$HERE/driver/0001-force-clevo-kb-backlight-type.patch"
KVER="$(uname -r)"
LED=/sys/class/leds/rgb:kbd_backlight

echo "==> dependencies"
apt-get update -qq || true
apt-get install -y --no-install-recommends build-essential dkms git "linux-headers-$KVER"

echo "==> fetch driver source (Commown fork @ ${PIN:0:7}) and apply patch"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git clone -q "$REPO" "$WORK/src"
git -C "$WORK/src" checkout -q "$PIN"
git -C "$WORK/src" apply "$PATCH"
echo "    patch applied."

VER="$(grep -Pom1 '.* \(\K.*(?=\) .*; urgency=.*)' "$WORK/src/debian/changelog")"
echo "    driver version: $VER"

echo "==> enumerate modules and generate dkms.conf"
# NB: this repo's Makefile uses M=$(PWD), so build from *inside* the dir
# (`make -C dir` would leave $(PWD) wrong and fail).
( cd "$WORK/src" && make ) >/dev/null 2>&1
{
  echo 'PACKAGE_NAME="tuxedo-drivers"'
  echo "PACKAGE_VERSION=\"$VER\""
  echo 'AUTOINSTALL="yes"'
  echo ''
  i=0
  for ko in $(cd "$WORK/src" && find src -name '*.ko' | sort); do
    echo "BUILT_MODULE_NAME[$i]=\"$(basename "$ko" .ko)\""
    echo "BUILT_MODULE_LOCATION[$i]=\"$(dirname "$ko")/\""
    echo "DEST_MODULE_LOCATION[$i]=\"/updates\""
    echo ''
    i=$((i+1))
  done
} > "$WORK/src/dkms.conf"
( cd "$WORK/src" && make clean ) >/dev/null 2>&1

echo "==> install via DKMS"
DEST="/usr/src/tuxedo-drivers-$VER"
dkms remove -m tuxedo-drivers -v "$VER" --all >/dev/null 2>&1 || true
rm -rf "$DEST"; cp -r "$WORK/src" "$DEST"
dkms add    -m tuxedo-drivers -v "$VER" >/dev/null
dkms install -m tuxedo-drivers -v "$VER" --force >/dev/null
echo "    $(dkms status tuxedo-drivers | tail -1)"

# --- figure out the backlight type the firmware reports -----------------------
echo "==> probing keyboard backlight type"
modprobe -r clevo_wmi clevo_acpi uniwill_wmi tuxedo_keyboard 2>/dev/null || true
MARK="kbdlight-probe-$$"                      # marker so we read only THIS probe's log
echo "$MARK" > /dev/kmsg 2>/dev/null || true
echo 'module tuxedo_keyboard +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
# force=-1 ensures we see the genuine firmware value, not any /etc/modprobe.d override
modprobe tuxedo_keyboard dyndbg=+p force_clevo_kb_backlight_type=-1 2>/dev/null || modprobe tuxedo_keyboard
modprobe clevo_acpi 2>/dev/null || true
modprobe clevo_wmi  2>/dev/null || true
sleep 1
PROBE="$(dmesg | sed -n "/$MARK/,\$p")"
# prefer the raw GET_SPECS type byte (authoritative); fall back to the parsed type line
DET_HEX="$(printf '%s\n' "$PROBE" | grep -oiE 'pointer\[0x0f\]: 0x[0-9a-f]+' | grep -oiE '0x[0-9a-f]+$' | tail -1 || true)"
[ -z "$DET_HEX" ] && DET_HEX="$(printf '%s\n' "$PROBE" | grep -oiE 'Keyboard backlight type: 0x[0-9a-f]+' | grep -oiE '0x[0-9a-f]+' | tail -1 || true)"
DET=$(( ${DET_HEX:-0} ))
echo "    firmware reports type: ${DET_HEX:-unknown}"

# known types: 0x01 fixed, 0x02 3-zone, 0x06 1-zone, 0xf3 per-key
FORCE="${FORCE_TYPE:-}"
if [ "$FORCE" = "auto" ]; then
    FORCE=""
elif [ -z "$FORCE" ]; then
    case "$DET" in
        1|2|6|243) FORCE="";  echo "    recognized type — no override needed";;
        *)         FORCE=6;   echo "    unrecognized type — forcing 0x06 (1-zone RGB)";;
    esac
fi

echo "==> persistent config (autoload + quirk)"
cat > /etc/modules-load.d/tuxedo-kbd.conf <<'EOF'
clevo_acpi
clevo_wmi
EOF
if [ -n "$FORCE" ]; then
    printf 'options tuxedo_keyboard force_clevo_kb_backlight_type=%s\n' "$FORCE" \
        > /etc/modprobe.d/tuxedo-kbd.conf
else
    rm -f /etc/modprobe.d/tuxedo-kbd.conf
fi

echo "==> reload with final settings"
modprobe -r clevo_wmi clevo_acpi uniwill_wmi tuxedo_keyboard 2>/dev/null || true
[ -n "$FORCE" ] && modprobe tuxedo_keyboard "force_clevo_kb_backlight_type=$FORCE" || modprobe tuxedo_keyboard
modprobe clevo_acpi 2>/dev/null || true
modprobe clevo_wmi  2>/dev/null || true
sleep 1

echo
if [ -e "$LED/brightness" ]; then
    echo "✅ keyboard backlight is now controllable: $LED"
    echo "   next: sudo ./install.sh   (installs the kbdlight CLI + GUI)"
else
    echo "❌ $LED did not appear."
    echo "   Your firmware reported type ${DET_HEX:-unknown}. Try a different value:"
    echo "     sudo FORCE_TYPE=2 ./install-driver.sh   # 3-zone"
    echo "     sudo FORCE_TYPE=243 ./install-driver.sh # per-key"
    echo "   If none work, your laptop may use the Uniwill (not Clevo) interface — please open an issue."
fi
