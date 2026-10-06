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

# Fuzzel/Dracula-ish palette with a near-black glass background.
BG = "#000000"
BG_OPACITY = 0.10
FG = "#f8f8f2"
PURPLE = "#bd93f9"
CYAN = "#8be9fd"
SELECTION = "#111111"
COMMENT = "#6272a4"
DARK = "#000000"
CAP_OPACITY = 0.22
BOUND_OPACITY = 0.34
MOD_OPACITY = 0.36

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
    "comma": ("b", 1), "period": ("n", 1), "space": ("space", 0), "dollar": ("dollar", 0),
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
    "back / close cheatsheet": "close", "launcher (fuzzel)": "launcher",
    "euphonica": "headphone",
}

# compact keycap captions (full labels stay in keys.json / cheatsheet.txt)
SHORT = {
    "play / pause": "play/pause", "previous": "previous", "next": "next",
    "seek -5s": "seek -5", "seek +5s": "seek +5",
    "random on/off": "random", "single on/off": "single",
    "volume -": "vol -", "volume +": "vol +", "mute": "mute",
    "wiremix peaks": "wiremix", "brightness": "brightness",
    "notifications": "notifications", "this cheatsheet": "cheatsheet",
    "back / close cheatsheet": "close", "launcher (fuzzel)": "launcher",
    "euphonica": "euphonica",
    "media play": "media play", "media next": "media next", "media prev": "media prev",
}


def icon(name, cx, cy, color, scale=1.0):
    s = []
    def path(d, fill="none"):
        s.append(f'<path d="{d}" fill="{fill}" stroke="{color}" '
                 f'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
    def text(t, dx=0, dy=0, size=13, weight="bold"):
        s.append(f'<text x="{dx}" y="{dy}" font-size="{size}" font-weight="{weight}" '
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
    elif name == "seekback":
        path("M -2,-8 L -10,0 L -2,8 Z", fill=color)
        path("M 10,-8 L 2,0 L 10,8 Z", fill=color)
    elif name == "seekfwd":
        path("M -10,-8 L -2,0 L -10,8 Z", fill=color)
        path("M 2,-8 L 10,0 L 2,8 Z", fill=color)
    elif name == "random":
        path("M -11,-5 L 6,3")
        path("M 11,5 L 4.8,5.7 L 7.2,0.3 Z", fill=color)
        path("M -11,5 L 6,-3")
        path("M 11,-5 L 7.2,-0.3 L 4.8,-5.7 Z", fill=color)
    elif name == "single":
        path("M -8,-7 L -2,-7")
        path("M 2,-7 L 4,-7")
        path("M 8,-7 L 4,-11 L 4,-3 Z", fill=color)
        path("M 8,7 L 2,7")
        path("M -2,7 L -4,7")
        path("M -8,7 L -4,3 L -4,11 Z", fill=color)
        text("1", 0, 0, 17)
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
    elif name == "launcher":
        path("M -9,-9 L -1,-9 L -1,-1 L -9,-1 Z", fill=color)
        path("M 1,-9 L 9,-9 L 9,-1 L 1,-1 Z", fill=color)
        path("M -9,1 L -1,1 L -1,9 L -9,9 Z", fill=color)
        path("M 1,1 L 9,1 L 9,9 L 1,9 Z", fill=color)
    elif name == "headphone":
        path("M -8,2 L -8,-1 A 8,8 0 0 1 8,-1 L 8,2")
        path("M -10,1 L -6,1 L -6,8 L -10,8 Z", fill=color)
        path("M 6,1 L 10,1 L 10,8 L 6,8 Z", fill=color)
    elif name == "capslock":
        path("M -8,0 L -8,9 L 8,9 L 8,0 Z", fill=color)
        path("M -5,0 L -5,-5 A 5,5 0 0 1 5,-5 L 5,0")
    elif name == "mouse1":
        path("M -8,-11 L 8,-11 Q 11,-11 11,-8 L 11,8 Q 11,11 8,11 L -8,11 "
             "Q -11,11 -11,8 L -11,-8 Q -11,-11 -8,-11 Z")
        path("M -11,-4 L 11,-4 M 0,-11 L 0,-4")
        path("M -11,-11 L 0,-11 L 0,-4 L -11,-4 Z", fill=color)
    elif name == "esc":
        path("M 10,-8 L 10,8 L -2,8 L -2,12 L -12,0 L -2,-12 L -2,-8 Z", fill=color)
    elif name == "tab":
        path("M -12,0 L -3,0 M -3,-6 L 4,0 L -3,6 Z", fill=color)
        path("M 6,-10 L 6,10 M 11,-10 L 11,10")
    else:
        path("M -6,0 A 6,6 0 1 0 6,0 A 6,6 0 1 0 -6,0", fill=color)
    return f'<g transform="translate({cx},{cy}) scale({scale})">{"".join(s)}</g>'


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
           f'<rect width="{W}" height="{H}" fill="{BG}" fill-opacity="{BG_OPACITY}"/>',
           f'<rect x="1" y="1" width="{W-2}" height="{H-2}" rx="14" fill="none" '
           f'stroke="{PURPLE}" stroke-opacity="0.45" stroke-width="1"/>',
           f'<text x="{M}" y="{M+22}" font-size="20" font-weight="bold" fill="{FG}">'
           f'HACKPI KEYS</text>',
           f'<text x="{W-M}" y="{M+22}" font-size="12" fill="{PURPLE}" text-anchor="end">'
           f'hold MOD (LGUI) + key</text>']

    board_y = M + TITLE_H
    for name, row, col, span, base in BOARD:
        x = M + col * (U + G)
        y = board_y + row * (U + G)
        w = span * U + (span - 1) * G
        bound = name in marks
        mod = name == "lgui"
        fill = PURPLE if mod else (SELECTION if bound else DARK)
        stroke = PURPLE if mod else (PURPLE if bound else COMMENT)
        fill_op = MOD_OPACITY if mod else (BOUND_OPACITY if bound else CAP_OPACITY)
        stroke_op = 0.75 if mod or bound else 0.45
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{U}" rx="9" '
                   f'fill="{fill}" fill-opacity="{fill_op}" stroke="{stroke}" '
                   f'stroke-opacity="{stroke_op}" stroke-width="1.5"/>')
        cx = x + w / 2
        marks_list = marks.get(name, [])
        base_size = 18 if len(base) <= 2 else 14
        if mod:
            out.append(f'<text x="{cx}" y="{y+U/2}" font-size="18" font-weight="bold" '
                       f'fill="{FG}" text-anchor="middle" dominant-baseline="central">MOD</text>')
        elif marks_list:
            for label, icon_name, layer in marks_list:
                out.append(icon(icon_name, cx, y + 18, CYAN, scale=0.7))
                short = SHORT.get(label, label)
                out.append(f'<text x="{cx}" y="{y+U-8}" font-size="9" fill="{FG}" '
                           f'text-anchor="middle">{short}</text>')
                if layer:
                    bx, by = x + w - 13, y + 13
                    out.append(f'<circle cx="{bx}" cy="{by}" r="9" fill="{BG}" '
                               f'fill-opacity="0.45" stroke="{PURPLE}" stroke-opacity="0.75"/>')
                    out.append(f'<text x="{bx}" y="{by}" font-size="11" font-weight="bold" '
                               f'fill="{PURPLE}" text-anchor="middle" dominant-baseline="central">{layer}</text>')
            out.append(f'<text x="{cx}" y="{y+U/2+4}" font-size="{base_size}" font-weight="bold" '
                       f'fill="{FG}" text-anchor="middle" dominant-baseline="central">{base}</text>')
        else:
            out.append(f'<text x="{cx}" y="{y+U/2}" font-size="{base_size}" font-weight="bold" '
                       f'fill="{COMMENT}" text-anchor="middle" dominant-baseline="central">{base}</text>')

    ly = board_y + ROWS * U + (ROWS - 1) * G + 22
    out.append(f'<text x="{M}" y="{ly}" font-size="13" font-weight="bold" fill="{FG}">'
               f'OTHER KEYS</text>')
    col_x, row_y = M, ly + 26
    for i, (key, label) in enumerate(legend):
        out.append(f'<text x="{col_x}" y="{row_y}" font-size="12" fill="{CYAN}">{key}</text>')
        out.append(f'<text x="{col_x+105}" y="{row_y}" font-size="12" fill="{FG}">{label}</text>')
        col_x += 236
        if i % 3 == 2:
            col_x, row_y = M, row_y + 24
    out.append(f'<text x="{W-M}" y="{H-M-4}" font-size="11" fill="{COMMENT}" text-anchor="end">'
               f'1 = Layer 1 (hold the L1 key)</text>')
    out.append("</svg>")

    with open(OUT, "w") as fh:
        fh.write("\n".join(out))
    print(f"wrote {OUT} ({W}x{H})")


if __name__ == "__main__":
    sys.exit(main())
