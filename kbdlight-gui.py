#!/usr/bin/env python3
"""
kbdlight-gui — a small GTK4/Adwaita app to control the keyboard backlight
on the COLORFUL P15 23 (tuxedo_keyboard, /sys/class/leds/rgb:kbd_backlight).

Talks to the sysfs LED directly. Passwordless control needs the udev rule
from this project installed (./install.sh); otherwise the files are root-only.
"""
import os
import sys

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gdk  # noqa: E402

LED = os.environ.get("KBDLIGHT_LED", "/sys/class/leds/rgb:kbd_backlight")

PRESETS = [
    ("White",   (255, 255, 255)), ("Warm",   (255, 160, 80)),
    ("Red",     (255, 0, 0)),     ("Orange", (255, 90, 0)),
    ("Yellow",  (255, 255, 0)),   ("Green",  (0, 255, 0)),
    ("Cyan",    (0, 255, 255)),   ("Blue",   (0, 0, 255)),
    ("Purple",  (160, 0, 255)),   ("Pink",   (255, 60, 120)),
]


def read(attr, default=None):
    try:
        with open(f"{LED}/{attr}") as f:
            return f.read().strip()
    except OSError:
        return default


def write(attr, value):
    try:
        with open(f"{LED}/{attr}", "w") as f:
            f.write(str(value))
        return True
    except OSError:
        return False


class Win(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Keyboard Backlight")
        self.set_default_size(420, 0)
        self._updating = False

        self.max = int(read("max_brightness", "255") or 255)
        self.rgb = self._read_rgb()
        self.level = int(read("brightness", "0") or 0)
        # remember a sensible "on" level for the toggle
        self.last_on = self.level if self.level > 0 else round(self.max * 0.6)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        save_btn = Gtk.Button(icon_name="document-save-symbolic",
                              tooltip_text="Set current as default (restored at boot/resume)")
        save_btn.connect("clicked", self.on_save)
        header.pack_end(save_btn)
        toolbar.add_top_bar(header)

        page = Adw.PreferencesPage()
        toolbar.set_content(page)

        # --- power + brightness ---------------------------------------------
        grp = Adw.PreferencesGroup(title="Backlight")
        page.add(grp)

        self.switch = Adw.SwitchRow(title="On", active=self.level > 0)
        self.switch.connect("notify::active", self.on_switch)
        grp.add(self.switch)

        brow = Adw.ActionRow(title="Brightness")
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.scale.set_hexpand(True)
        self.scale.set_size_request(220, -1)
        self.scale.set_draw_value(True)
        self.scale.set_value_pos(Gtk.PositionType.RIGHT)
        self.scale.set_value(self._pct(self.level))
        self.scale.connect("value-changed", self.on_scale)
        brow.add_suffix(self.scale)
        grp.add(brow)

        # --- colour ----------------------------------------------------------
        cgrp = Adw.PreferencesGroup(title="Colour")
        page.add(cgrp)

        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                           max_children_per_line=5, min_children_per_line=5,
                           row_spacing=8, column_spacing=8, margin_top=6,
                           margin_bottom=6, margin_start=6, margin_end=6)
        for name, rgb in PRESETS:
            flow.append(self._swatch(name, rgb))
        crow = Adw.PreferencesRow(activatable=False)
        crow.set_child(flow)
        cgrp.add(crow)

        # custom colour picker
        pick = Adw.ActionRow(title="Custom colour")
        try:
            self.colorbtn = Gtk.ColorDialogButton.new(Gtk.ColorDialog())
            self.colorbtn.set_rgba(self._as_rgba(self.rgb))
            self.colorbtn.connect("notify::rgba", self.on_colorbtn)
            self.colorbtn.set_valign(Gtk.Align.CENTER)
            pick.add_suffix(self.colorbtn)
        except Exception:
            pick.set_subtitle("(color picker unavailable; use the swatches)")
        cgrp.add(pick)

        # writability hint
        if not os.access(f"{LED}/brightness", os.W_OK):
            warn = Adw.PreferencesGroup()
            row = Adw.ActionRow(
                title="Read-only access",
                subtitle="Run ./install.sh once for passwordless control.")
            row.add_prefix(Gtk.Image.new_from_icon_name("dialog-warning-symbolic"))
            warn.add(row)
            page.add(warn)

        self.set_content(toolbar)

    # ---- helpers -----------------------------------------------------------
    def _pct(self, raw):
        return round(raw * 100 / self.max)

    def _raw(self, pct):
        return round(pct * self.max / 100)

    def _read_rgb(self):
        try:
            r, g, b = (int(x) for x in (read("multi_intensity", "255 255 255")).split())
            return (r, g, b)
        except Exception:
            return (255, 255, 255)

    def _as_rgba(self, rgb):
        c = Gdk.RGBA()
        c.red, c.green, c.blue, c.alpha = rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0
        return c

    def _swatch(self, name, rgb):
        btn = Gtk.Button(tooltip_text=name)
        btn.set_size_request(48, 40)
        css = Gtk.CssProvider()
        css.load_from_data(
            ("button{background:#%02x%02x%02x;border-radius:8px;"
             "box-shadow:inset 0 0 0 1px rgba(0,0,0,.25);}" % rgb).encode())
        btn.get_style_context().add_provider(css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        btn.connect("clicked", lambda _b, c=rgb: self.set_color(c))
        return btn

    def _apply(self):
        write("multi_intensity", "%d %d %d" % self.rgb)
        write("brightness", self.level)   # re-write triggers EC update

    # ---- handlers ----------------------------------------------------------
    def set_color(self, rgb):
        self.rgb = rgb
        if self.level == 0:                # turning colour on from off
            self.level = self.last_on
            self._updating = True
            self.switch.set_active(True)
            self.scale.set_value(self._pct(self.level))
            self._updating = False
        if hasattr(self, "colorbtn"):
            self._updating = True
            self.colorbtn.set_rgba(self._as_rgba(rgb))
            self._updating = False
        self._apply()

    def on_colorbtn(self, btn, _param):
        if self._updating:
            return
        c = btn.get_rgba()
        self.set_color((round(c.red * 255), round(c.green * 255), round(c.blue * 255)))

    def on_switch(self, sw, _param):
        if self._updating:
            return
        if sw.get_active():
            self.level = self.last_on or self._raw(60)
            self._updating = True
            self.scale.set_value(self._pct(self.level))
            self._updating = False
        else:
            if self.level > 0:
                self.last_on = self.level
            self.level = 0
        self._apply()

    def on_scale(self, scale):
        if self._updating:
            return
        self.level = self._raw(scale.get_value())
        if self.level > 0:
            self.last_on = self.level
        self._updating = True
        self.switch.set_active(self.level > 0)
        self._updating = False
        self._apply()

    def on_save(self, _btn):
        # delegate to the CLI so boot/resume restore uses the same state file
        GLib.spawn_command_line_async("kbdlight save")
        toast = Gtk.Label(label="Saved")  # minimal feedback
        toast.set_visible(False)


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id="in.tsbi.kbdlight")

    def do_activate(self):
        if not os.path.exists(f"{LED}/brightness"):
            dlg = Adw.AlertDialog(
                heading="No keyboard backlight found",
                body=f"{LED} does not exist.\nIs the tuxedo_keyboard driver loaded?")
            dlg.add_response("ok", "OK")
            win = Adw.ApplicationWindow(application=self)
            win.present()
            dlg.present(win)
            return
        Win(self).present()


if __name__ == "__main__":
    sys.exit(App().run(sys.argv))
