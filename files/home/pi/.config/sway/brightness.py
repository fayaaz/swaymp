#!/usr/bin/env python3
"""Software screen brightness for the Hackberry Pi.

The HyperPixel4 panel backlight is on/off only (max_brightness=1), so this
dims the panel via gamma with gammastep, opened from a sway keybind like
wiremix. The last value is saved and re-applied by --restore at login.
"""
import curses
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

STATE = Path.home() / ".cache" / "hackpi-brightness"
MIN = 0.1
MAX = 1.0
STEP = 0.05
NEUTRAL_TEMP = 6500


def load():
    try:
        value = float(STATE.read_text().strip())
        return min(MAX, max(MIN, value))
    except (OSError, ValueError):
        return MAX


def save(value):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(f"{value:.2f}\n")


def gammastep_pids():
    result = subprocess.run(
        ["pgrep", "-x", "gammastep"], capture_output=True, text=True
    )
    return [int(pid) for pid in result.stdout.split()]


def apply(value):
    for pid in gammastep_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if gammastep_pids():
        time.sleep(0.2)
    subprocess.Popen(
        ["gammastep", "-O", str(NEUTRAL_TEMP), "-b", f"{value:.2f}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    save(value)


def bar(value, width):
    filled = round((value - MIN) / (MAX - MIN) * width)
    return "[" + "#" * filled + "-" * (width - filled) + "]"


def tui(stdscr):
    curses.curs_set(0)
    stdscr.keypad(True)
    value = load()
    if not gammastep_pids():
        apply(value)
    while True:
        stdscr.erase()
        height, width = stdscr.getmaxyx()
        title = "Brightness (software dim)"
        stdscr.addstr(1, max(0, (width - len(title)) // 2), title, curses.A_BOLD)
        art = f"{round(value * 100):3d}%  {bar(value, max(10, width - 18))}"
        stdscr.addstr(height // 2, max(0, (width - len(art)) // 2), art)
        hint = "up/k: +5%   down/j: -5%   r: 100%   q: quit"
        stdscr.addstr(height - 2, max(0, (width - len(hint)) // 2), hint)
        stdscr.refresh()
        key = stdscr.getch()
        if key in (ord("q"), 27):
            break
        if key in (curses.KEY_UP, ord("k"), ord("+"), curses.KEY_RIGHT, ord("l")):
            value = min(MAX, round(value + STEP, 2))
            apply(value)
        elif key in (curses.KEY_DOWN, ord("j"), ord("-"), curses.KEY_LEFT, ord("h")):
            value = max(MIN, round(value - STEP, 2))
            apply(value)
        elif key == ord("r"):
            value = MAX
            apply(value)


def main():
    args = sys.argv[1:]
    if args and args[0] == "--set" and len(args) > 1:
        value = min(MAX, max(MIN, float(args[1]) / 100))
        apply(value)
        print(f"{round(value * 100)}%")
        return
    if args and args[0] == "--restore":
        if STATE.exists():
            apply(load())
        return
    curses.wrapper(tui)


if __name__ == "__main__":
    main()
