#!/usr/bin/env python3
"""Transparent overlay viewer for the Hackberry cheatsheet (GTK3).

Shows cheatsheet.svg in a borderless, fully transparent window so the
card's rounded corners show the workspace behind. Wayland app_id is
"cheatsheet" (via set_prgname), so the sway rule and cheatsheet.sh
toggle keep working unchanged.
"""
import os
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

DIR = os.path.dirname(os.path.abspath(__file__))
SVG = os.path.join(DIR, "cheatsheet.svg")
W, H = 700, 520


def quit_viewer(*args):
    # Normal exit (click / key / toggle) removes our PID record so the
    # launch watchdog in cheatsheet.sh stays silent; a crash leaves it
    # behind, which is exactly what should report an error.
    pidfile = os.environ.get("CHEATSHEET_PIDFILE")
    if pidfile:
        try:
            os.unlink(pidfile)
        except OSError:
            pass
    Gtk.main_quit()


def on_key(win, event):
    if Gdk.keyval_name(event.keyval) in ("Escape", "q", "F13", "F11"):
        quit_viewer()


def main():
    GLib.set_prgname("cheatsheet")
    win = Gtk.Window()
    win.set_title("cheatsheet")
    win.set_decorated(False)
    win.set_resizable(False)
    win.set_app_paintable(True)
    win.set_default_size(W, H)
    visual = win.get_screen().get_rgba_visual()
    if visual is not None:
        win.set_visual(visual)
    css = Gtk.CssProvider()
    css.load_from_data(b"window { background-color: transparent; border: none; }")
    win.get_style_context().add_provider(css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    try:
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(SVG, W, H)
    except GLib.Error as err:
        print(f"cheatsheet-viewer: cannot load {SVG}: {err}", file=sys.stderr)
        return 1
    win.add(Gtk.Image.new_from_pixbuf(pixbuf))
    win.connect("destroy", quit_viewer)
    win.connect("button-press-event", quit_viewer)
    win.connect("key-press-event", on_key)
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
