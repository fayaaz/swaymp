#!/usr/bin/env python3
"""Render keys.json as a HackberryPi 9900 keyboard diagram (SVG).

Physical layout taken from ZitaoTech/HackberryPiCM5 (Keyboard/ + keymap images).
"""
import json
import os
import sys

DIR = os.path.dirname(os.path.abspath(__file__))
KEYS = os.path.join(DIR, "keys.json")
OUT = os.path.join(DIR, "cheatsheet.svg")

U, G, M = 64, 6, 14          # key unit, gap, outer margin
ROWS = 5
W = M * 2 + 10 * U + 9 * G
TITLE_H, LEGEND_H = 38, 118
H = M * 2 + TITLE_H + ROWS * U + (ROWS - 1) * G + LEGEND_H

# (row, col, span) for every physical keycap; base label = Layer 0 legend.
BOARD = [
    ("capslock", 0, 0, 2, "Caps"), ("lgui", 0, 2, 2, "MOD"), ("mouse1", 0, 4, 1, "LMB"),
    ("esc", 0, 5, 2, "Esc"), ("tab", 0, 7, 2, "Tab"),
    ("q", 1, 0, 1, "Q"), ("w", 1, 1, 1, "W"), ("e", 1, 2, 1, "E"), ("r", 1, 3, 1, "R"),
    ("t", 1, 4, 1, "T"), ("y", 1, 5, 1, "Y"), ("u", 1, 6, 1, "U"), ("i", 1, 7, 1, "I"),
    ("o", 1, 8, 1, "O"), ("p", 1, 9, 1, "P"),
    ("a", 2, 0, 1, "A"), ("s", 2, 1, 1, "S"), ("d", 2, 2, 1, "D"), ("f", 2, 3, 1, "F"),
    ("g", 2, 4, 1, "G"), ("h", 2, 5, 1, "H"), ("j", 2, 6, 1, "J"), ("k", 2, 7, 1, "K"),
    ("l", 2, 8, 1, "L"), ("bspace", 2, 9, 1, "Del"),
    ("shift", 3, 0, 1, "Shift"), ("z", 3, 1, 1, "Z"), ("x", 3, 2, 1, "X"), ("c", 3, 3, 1, "C"),
    ("v", 3, 4, 1, "V"), ("b", 3, 5, 1, "B"), ("n", 3, 6, 1, "N"), ("m", 3, 7, 1, "M"),
    ("dollar", 3, 8, 1, "$"), ("enter", 3, 9, 1, "Enter"),
    ("ctrl", 4, 1, 1, "Ctrl"), ("alt", 4, 2, 1, "Alt"), ("space", 4, 3, 4, "Space"),
    ("layer1", 4, 7, 1, "L1"), ("layer2", 4, 8, 1, "L2"),
]

# keysym -> physical keycap + layer badge (comma/period live on Layer 1)
KEYSYM = {
    "q": ("q", 0), "w": ("w", 0), "e": ("e", 0), "r": ("r", 0), "t": ("t", 0),
    "y": ("y", 0), "u": ("u", 0), "i": ("i", 0), "o": ("o", 0), "p": ("p", 0),
    "a": ("a", 0), "s": ("s", 0), "d": ("d", 0), "f": ("f", 0), "g": ("g", 0),
    "h": ("h", 0), "j": ("j", 0), "k": ("k", 0), "l": ("l", 0),
    "z": ("z", 0), "x": ("x", 0), "c": ("c", 0), "v": ("v", 0), "b": ("b", 0),
    "n": ("n", 0), "m": ("m", 0),
    "comma": ("b", 1), "period": ("n", 1), "space": ("space", 0),
    "F1": ("capslock", 2), "F2": ("esc", 2), "F3": ("tab", 2),
}

ICONS = {
    "play / pause": "playpause", "media play": "playpause",
    "previous": "prev", "media prev": "prev",
    "next": "next", "media next": "next",
    "seek -5s": "seekback", "seek +5s": "seekfwd",
    "random on/off": "random", "single on/off": "single",
    "volume -": "volminus", "volume +": "volplus", "mute": "mute",
    "wiremix peaks": "meter", "brightness": "sun",
    "notifications": "bell", "this cheatsheet": "help",
    "back / close cheatsheet": "close",
}

# compact keycap captions (full labels stay in keys.json / cheatsheet.txt)
SHORT = {
    "play / pause": "play/pause", "previous": "previous", "next": "next",
    "seek -5s": "seek -5", "seek +5s": "seek +5",
    "random on/off": "random", "single on/off": "single",
    "volume -": "vol -", "volume +": "vol +", "mute": "mute",
    "wiremix peaks": "wiremix", "brightness": "brightness",
    "notifications": "notify", "this cheatsheet": "cheatsheet",
    "back / close cheatsheet": "close",
    "media play": "media play", "media next": "media next", "media prev": "media prev",
}


def icon(name, cx, cy, color):
    s = []
    def path(d, fill="none"):
        s.append(f'<path d="{d}" fill="{fill}" stroke="{color}" '
                 f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
    def text(t, dx=0, dy=0, size=13, weight="bold"):
        s.append(f'<text x="{cx+dx}" y="{cy+dy}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{color}" text-anchor="middle" dominant-baseline="central">{t}</text>')
    if name == "playpause":
        path("M -11,-8 L -2,0 L -11,8 Z", fill=color)
        path("M 4,-8 L 4,8 M 10,-8 L 10,8")
    elif name == "prev":
        path("M -12,-8 L -12,8")
        path("M -9,0 L -1,-8 L -1,8 Z", fill=color)
        path("M -1,0 L 7,-8 L 7,8 Z", fill=color)
    elif name == "next":
        path("M 12,-8 L 12,8")
        path("M 9,0 L 1,-8 L 1,8 Z", fill=color)
        path("M 1,0 L -7,-8 L -7,8 Z", fill=color)
    elif name in ("seekback", "seekfwd"):
        d = "M 8,-6 A 9,9 0 1 0 9,4" if name == "seekback" else "M -8,-6 A 9,9 0 1 1 -9,4"
        path(d)
        path("M 8,-11 L 8,-6 L 3,-6" if name == "seekback" else "M -8,-11 L -8,-6 L -3,-6")
        text("5", 0, 1, 11)
    elif name == "random":
        path("M -11,-5 L -3,-5 L 11,6 M 6,6 L 11,6 L 11,1")
        path("M -11,6 L -3,6 L 11,-5 M 6,-5 L 11,-5 L 11,-10")
    elif name == "single":
        path("M 6,-8 A 9,9 0 1 0 9,1 M 9,-4 L 9,1 L 4,1")
        text("1", -2, 0, 13)
    elif name in ("volminus", "volplus", "mute"):
        path("M -11,-4 L -7,-4 L -1,-9 L -1,9 L -7,4 L -11,4 Z", fill=color)
        if name == "volminus":
            path("M 4,0 L 11,0")
        elif name == "volplus":
            path("M 4,0 L 11,0 M 7.5,-3.5 L 7.5,3.5")
        else:
            path("M 4,-5 L 11,2 M 11,-5 L 4,2")
    elif name == "meter":
        for i, h in enumerate((6, 12, 8, 15)):
            x = -10 + i * 7
            path(f"M {x},8 L {x},{8-h}")
    elif name == "sun":
        path("M 0,-4 A 4,4 0 1 0 0,4 A 4,4 0 1 0 0,-4")
        path("M 0,-10 L 0,-7 M 0,7 L 0,10 M -10,0 L -7,0 M 7,0 L 10,0 "
             "M -7,-7 L -5,-5 M 5,5 L 7,7 M 7,-7 L 5,-5 M -5,5 L -7,7")
    elif name == "bell":
        path("M -8,4 L -8,-2 A 8,8 0 0 1 8,-2 L 8,4 L 10,7 L -10,7 Z")
        path("M -3,10 A 3,3 0 0 0 3,10")
    elif name == "help":
        text("?", 0, 0, 20)
    elif name == "close":
        path("M -8,-8 L 8,8 M 8,-8 L -8,8")
    else:
        path("M -6,0 A 6,6 0 1 0 6,0 A 6,6 0 1 0 -6,0", fill=color)
    return "".join(s)


def main():
    binds = json.load(open(KEYS))["binds"]
    marks, legend = {}, []
    for b in binds:
        key, label = b["key"], b["label"]
        icon_name = b.get("icon") or ICONS.get(label, "dot")
        if key.startswith("$mod+"):
            keysym = key.split("+", 1)[1]
            if keysym in KEYSYM:
                cap, layer = KEYSYM[keysym]
                marks.setdefault(cap, []).append((label, icon_name, layer))
            else:
                legend.append((key, label))
        else:
            legend.append((key, label))

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}">',
           f'<rect width="{W}" height="{H}" fill="#14171c"/>',
           f'<text x="{M}" y="{M+22}" font-size="20" font-weight="bold" fill="#e8eef7">'
           f'HACKPI KEYS</text>',
           f'<text x="{W-M}" y="{M+22}" font-size="12" fill="#8b95a7" text-anchor="end">'
           f'hold MOD (LGUI) + key</text>']

    board_y = M + TITLE_H
    for name, row, col, span, base in BOARD:
        x = M + col * (U + G)
        y = board_y + row * (U + G)
        w = span * U + (span - 1) * G
        bound = name in marks
        mod = name == "lgui"
        fill = "#7a3b12" if mod else ("#1b4f7a" if bound else "#23272e")
        stroke = "#e0a35c" if mod else ("#59a7e6" if bound else "#333842")
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{U}" rx="9" '
                   f'fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>')
        out.append(f'<text x="{x+8}" y="{y+16}" font-size="11" fill="#93a0b3">{base}</text>')
        cx, cy = x + w / 2, y + U / 2 + 3
        if mod:
            out.append(f'<text x="{cx}" y="{cy}" font-size="15" font-weight="bold" '
                       f'fill="#ffe6c9" text-anchor="middle" dominant-baseline="central">MOD</text>')
        for label, icon_name, layer in marks.get(name, []):
            out.append(icon(icon_name, cx, cy - 6, "#eaf3ff"))
            short = SHORT.get(label, label)
            out.append(f'<text x="{cx}" y="{y+U-8}" font-size="9" fill="#cfe3f7" '
                       f'text-anchor="middle">{short}</text>')
            if layer:
                bx, by = x + w - 13, y + 13
                out.append(f'<circle cx="{bx}" cy="{by}" r="9" fill="#0f1115" stroke="#59a7e6"/>')
                out.append(f'<text x="{bx}" y="{by}" font-size="11" font-weight="bold" '
                           f'fill="#9ed1ff" text-anchor="middle" dominant-baseline="central">{layer}</text>')

    ly = board_y + ROWS * U + (ROWS - 1) * G + 22
    out.append(f'<text x="{M}" y="{ly}" font-size="13" font-weight="bold" fill="#e8eef7">'
               f'OTHER KEYS</text>')
    col_x, row_y = M, ly + 26
    for i, (key, label) in enumerate(legend):
        out.append(f'<text x="{col_x}" y="{row_y}" font-size="12" fill="#9ed1ff">{key}</text>')
        out.append(f'<text x="{col_x+105}" y="{row_y}" font-size="12" fill="#c4cfdc">{label}</text>')
        col_x += 236
        if i % 3 == 2:
            col_x, row_y = M, row_y + 24
    out.append(f'<text x="{W-M}" y="{H-M-4}" font-size="11" fill="#7d8798" text-anchor="end">'
               f'1 = Layer 1 (hold the L1 key)</text>')
    out.append("</svg>")

    with open(OUT, "w") as fh:
        fh.write("\n".join(out))
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    sys.exit(main())
