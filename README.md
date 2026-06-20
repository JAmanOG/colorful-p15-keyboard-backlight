# Keyboard backlight control for COLORFUL / Tongfang laptops on Linux

Enables and controls the **RGB keyboard backlight** on the **COLORFUL P15 23**
(and likely other Tongfang/Clevo-based laptops) under Linux — something these
machines ship **no Linux software for**. You get a CLI (`kbdlight`), a small
GTK4 GUI, working `Fn` brightness keys, and automatic restore at boot / after
suspend.

> **TL;DR** — the keyboard backlight *is* supported by the open-source
> `tuxedo_keyboard` driver, but the firmware reports an **unrecognized backlight
> type (`0x26`)** so the driver registers nothing. A one-line patch lets us tell
> the driver "treat it as 1-zone RGB", and everything works.

---

## Does this apply to my laptop?

Likely **yes** if:

- It's a **COLORFUL** (e.g. P15 23) or other **Tongfang/Uniwill/Clevo** rebrand,
- The keyboard backlight has **no control** in Linux (nothing in
  `/sys/class/leds/*kbd_backlight*`), and `lsusb` shows **no** dedicated RGB
  controller (the light is driven by the embedded controller, not USB),
- On Windows it's controlled by a vendor "Control Center" app and the
  `Fn` keys.

Quick check:
```bash
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name   # COLORFUL / P15 23 ...
ls /sys/class/leds | grep -i kbd                                  # (probably nothing)
```

## What you get

| Component | What it does |
|---|---|
| patched `tuxedo_keyboard` (via DKMS) | exposes `/sys/class/leds/rgb:kbd_backlight` (brightness + RGB) |
| `kbdlight` | command-line control (on/off/brightness/colour) |
| `kbdlight-gui` | GTK4/Adwaita app — slider, colour swatches, custom colour picker |
| `Fn` keys | `Fn`+`*` toggle, `Fn`+`+/-` brightness — via the `kbdlight-keys` listener service (works on any desktop, no relogin) |
| GNOME slider | native keyboard-backlight slider in the system menu (after a relogin) |
| restore service | re-applies your setting at boot and after suspend/lock |

On Windows the vendor app only offers a handful of preset colours — on Linux you
get the **full 0–255 RGB range**.

---

## Install (from scratch)

Tested on **Ubuntu 24.04 / kernel 6.17**. Needs internet (to fetch the driver
source) and `sudo`.

```bash
git clone https://github.com/JAmanOG/colorful-p15-keyboard-backlight
cd colorful-p15-keyboard-backlight

sudo ./install-driver.sh     # build + DKMS-install the patched driver, set up autoload
sudo ./install.sh            # install the kbdlight CLI + GUI + udev + restore service
```

`install-driver.sh` auto-detects your backlight type. If the firmware reports a
**recognized** type it changes nothing; if it reports an **unknown** type (like
`0x26`) it forces 1-zone RGB. To force a specific layout:

```bash
sudo FORCE_TYPE=2   ./install-driver.sh   # 3-zone RGB
sudo FORCE_TYPE=243 ./install-driver.sh   # per-key RGB
sudo FORCE_TYPE=auto ./install-driver.sh  # never force (trust firmware)
```

The `Fn` keys (`Fn`+`*` / `Fn`+`+/-`) work immediately via the `kbdlight-keys`
listener service. The native GNOME *slider* additionally needs one logout/login
(so gnome-settings-daemon picks up the new LED).

## Usage

```bash
kbdlight on | off | toggle
kbdlight set 60                 # brightness %
kbdlight up | down              # +/- 10 %
kbdlight color red              # named colour
kbdlight color "#33ccff" 80     # hex colour at 80 %
kbdlight colors                 # list names
kbdlight status
kbdlight save                   # remember current as the boot/resume default
```

GUI: launch **Keyboard Backlight** from your app menu, or run `kbdlight-gui`.
The `Fn` keys and GNOME's system-menu slider also work once installed.

---

## How it works (the diagnosis)

1. The P15 23 is a **Tongfang/Uniwill barebones**; its backlight is on the
   **embedded controller**, reachable through the **Clevo** WMI/ACPI interface.
   (No USB RGB chip → OpenRGB / `ite8291` tools can't see it.)
2. `tuxedo_keyboard` asks the firmware for the keyboard type via
   `CLEVO_CMD_GET_SPECS`. Known types are `0x01` fixed, `0x02` 3-zone,
   `0x06` 1-zone, `0xf3` per-key. **This machine answers `0x26`**, which isn't in
   the table, so the driver registers no LED.
3. The patch (`driver/0001-force-clevo-kb-backlight-type.patch`) adds a module
   parameter `force_clevo_kb_backlight_type`. We force **`6` (1-zone RGB)**; the
   EC happily accepts the standard Clevo RGB commands and a normal LED appears.

### Find your own backlight type
If `install-driver.sh` can't get the light working, see what your firmware
reports:
```bash
sudo modprobe -r clevo_wmi clevo_acpi tuxedo_keyboard 2>/dev/null
echo 'module tuxedo_keyboard +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
sudo modprobe tuxedo_keyboard dyndbg=+p; sudo modprobe clevo_acpi clevo_wmi
sudo dmesg | grep -i "backlight type"
```
Report the value in an issue with your `sys_vendor` / `product_name` so others
with the same model are covered.

---

## Troubleshooting

**Backlight gone after a kernel update** — DKMS should rebuild automatically; if not:
```bash
sudo dkms autoinstall
sudo modprobe clevo_acpi clevo_wmi
ls /sys/class/leds/rgb:kbd_backlight
```

**`Fn` keys do nothing** — check the listener service:
```bash
systemctl status kbdlight-keys.service          # should be active (running)
sudo journalctl -u kbdlight-keys.service
```
The keys emit `KEY_KBDILLUMUP/DOWN/TOGGLE` on the "TUXEDO Keyboard" input device;
`install.sh` clears GNOME's built-in bindings for them so the listener is the
sole handler. (The native GNOME *slider* is separate and needs one relogin.)

**Fn keys do double brightness steps** — both the listener and GNOME are acting.
Re-run `sudo ./install.sh` (it clears the GNOME bindings), or set them empty:
`gsettings set org.gnome.settings-daemon.plugins.media-keys keyboard-brightness-up-static "@as []"` (and `-down-`/`-toggle-`).

**"cannot write …/brightness"** — re-run `sudo ./install.sh` (sets the udev rule).
Default access is granted to the `users` group; override with
`sudo KBDLIGHT_GROUP=video ./install.sh`.

**Want independent colour zones** — try `sudo FORCE_TYPE=2 ./install-driver.sh`.
If `/sys/class/leds/` then shows multiple `rgb:kbd_backlight*` nodes that light
independently, keep it; otherwise go back to the default.

## Uninstall

```bash
sudo ./uninstall.sh                                   # removes the tool
sudo dkms remove tuxedo-drivers/<version> --all       # removes the driver (see: dkms status)
sudo rm -f /etc/modprobe.d/tuxedo-kbd.conf /etc/modules-load.d/tuxedo-kbd.conf
```

## Repo layout

```
install-driver.sh   build + DKMS-install the patched tuxedo_keyboard driver
install.sh          install the kbdlight CLI/GUI + udev + restore service
uninstall.sh
kbdlight            CLI
kbdlight-gui.py     GTK4/Adwaita GUI
kbdlight-listen     Fn-key listener (maps KBDILLUM keys -> kbdlight)
driver/0001-force-clevo-kb-backlight-type.patch   the one-line driver fix
data/               udev rule, .desktop, systemd units (restore, resume, keys)
```

## Credits

Built on **[tuxedo-drivers](https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers)**
by TUXEDO Computers, via the **[Commown fork](https://gitlab.com/commown/tuxedo-drivers)**
(GPL-2.0+). The driver patch is a derivative of that GPL-2.0+ code; the
`kbdlight` CLI/GUI and installers are original glue. Contributions for other
COLORFUL/Tongfang models welcome — please include your DMI strings and the
backlight-type value from the diagnosis above.
