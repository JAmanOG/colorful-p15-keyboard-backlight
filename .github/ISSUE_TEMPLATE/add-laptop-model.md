---
name: Add / fix support for a laptop model
about: Report a COLORFUL / Tongfang / Clevo laptop so its keyboard backlight can be supported
title: "[model] keyboard backlight: "
labels: hardware-report
---

**Laptop**
- `sys_vendor` / `product_name`
  (`cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name`):
- Distro / kernel (`. /etc/os-release; echo $PRETTY_NAME; uname -r`):
- On Windows the backlight is: <!-- single colour / a few presets / full RGB / zones? -->

**Backlight type the firmware reports**
Run the diagnosis from the README, then paste the value:
```
sudo dmesg | grep -i "backlight type"
```
Type: `0x__`

**Result**
- [ ] `install-driver.sh` auto-detected it and the backlight works
- [ ] Needed `FORCE_TYPE=__` (which value worked?)
- [ ] Didn't work

**Extra info**
```
ls /sys/class/leds | grep -i kbd
lsusb
```
