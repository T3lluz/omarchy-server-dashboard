#!/usr/bin/env python3
"""
Build Pixels.js, Server Dashboard's pixel icons, from Pixelarticons (MIT,
https://pixelarticons.com). The mark itself (two server units, after the app
icon) is drawn by Model.js (serverMark), since its lights move; "server" here
is that drawing with its lights lit, for places that only need the shape.

Pixelarticons are drawn on a 24-unit grid with two-unit strokes. Their SVGs
are outlines of rectangles, so each icon turns into an exact grid of pixels:
a cell is on when its centre is inside the shape. PixelIcon.qml draws the
grid as rectangles on whole device pixels, so the icons stay sharp at any
scale. Small sizes use the same grid halved (see `halve`). Run from the repo root:

    python3 scripts/fetch-pixel-icons.py          # --show prints each grid and its parts

The SVGs it fetched are kept in pixels/, so a rerun with every SVG there
works offline; a new name in ICONS fetches the package again.

Icons that act themselves out (Motion.js) are also cut into parts, so only
the piece that moves does: the gauge's needle, the box's lid, the bell's
clapper. See PARTS.
"""

import io
import json
import os
import re
import sys
import tarfile
import urllib.request

VERSION = "2.4.2"
TARBALL = "https://registry.npmjs.org/pixelarticons/-/pixelarticons-%s.tgz" % VERSION
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# The icons the panel draws, by the name Pixelarticons gives them.
ICONS = [
    # The rooms.
    "speed-fast", "database", "sort-vertical", "package", "list-box", "warning-diamond",
    # The System room's cells and the bar's readings.
    "cpu", "memory-stick", "thermometer", "arrow-down", "arrow-up",
    # Containers and the actions.
    "play", "stop", "reload", "terminal", "chart-line", "power",
    # The panel's buttons and the kit's glyphs.
    "chevron-down", "settings-cog", "arrow-left", "check", "close", "download",
    "hourglass", "layout", "bell", "link", "key",
]

# Drawn here on a 12-cell grid (each cell two units), in Pixelarticons'
# weight: one-cell lines, corners cut square. Model.serverMark draws the same
# shape in parts; tests/model.test.js checks they agree.
CUSTOM = {
    # Two server units, each with a light and a label line, as on the app icon.
    "server": [
        "..########..",
        ".#........#.",
        ".#.##.###.#.",
        ".#........#.",
        "..########..",
        "............",
        "..########..",
        ".#........#.",
        ".#.##.###.#.",
        ".#........#.",
        "..########..",
        "............",
    ],
}


# The parts of an icon that move on their own, for Motion.js, on the 12 grid.
# "cut" takes cells out of the icon's own art: the first region
# ([x0, y0, x1, y1), the end exclusive) that holds a cell gets it, and the
# rest stays in "base". "add" is art drawn here, cell by cell, that shows only
# when Motion.js says so: the needle's other angles, a mercury column, a
# terminal's cursor. On the 24 grid added art starts on the icon's own stroke
# parity, or on "add-shift" where the art around it uses the other one. An
# icon with no entry moves whole, as "base".
PARTS = {
    "speed-fast": {
        "cut": {"needle": [(7, 3, 10, 6)]},
        "add": {
            "needle-right": [(7, 6), (8, 6), (9, 6)],
            "needle-up": [(4, 5), (3, 4)],
            "needle-zero": [(2, 6), (3, 6), (4, 6)],
        },
        # The hub sits on even units though the arc is on odd ones.
        "add-shift": (0, 1),
    },
    "database": {"cut": dict(
        [("band-a%d" % i, [(4 + i, 6, 5 + i, 7)]) for i in range(4)]
        + [("band-b%d" % i, [(4 + i, 8, 5 + i, 9)]) for i in range(4)])},
    "sort-vertical": {"cut": {"up": [(0, 0, 6, 12)], "down": [(6, 0, 12, 12)]}},
    "package": {"cut": {"lid": [(2, 0, 10, 5)]}},
    "list-box": {"cut": {"line1": [(3, 3, 9, 4)], "line2": [(3, 5, 9, 6)], "line3": [(3, 7, 9, 8)]}},
    "warning-diamond": {"cut": {"bang": [(5, 3, 7, 8)]}},
    "cpu": {"cut": {
        "pins-top": [(0, 0, 12, 1)], "pins-bottom": [(0, 10, 12, 12)],
        "pins-left": [(0, 1, 1, 10)], "pins-right": [(10, 1, 12, 10)],
        "die": [(3, 3, 8, 8)],
    }},
    "memory-stick": {"cut": {"chip1": [(3, 4, 4, 6)], "chip2": [(5, 4, 6, 6)], "chip3": [(7, 4, 8, 6)]}},
    "thermometer": {"add": dict(("mercury%d" % i, [(5, 8 - i)]) for i in range(1, 6))},
    "stop": {"cut": {"dot": [(5, 5, 7, 7)]}},
    "download": {"cut": {"arrow": [(2, 0, 9, 9)]}},
    "layout": {"cut": {"divider": [(4, 5, 5, 9)]}},
    "bell": {"cut": {"body": [(0, 0, 12, 8)], "clapper": [(0, 8, 12, 12)]}},
    "link": {"cut": {"bar": [(3, 5, 8, 6)], "left": [(0, 0, 5, 12)], "right": [(5, 0, 12, 12)]}},
    "check": {"cut": {"short": [(0, 0, 5, 12)], "long": [(5, 0, 12, 12)]}},
    "close": {"cut": {"tips": [(0, 2, 12, 3), (0, 8, 12, 9)]}},
    "terminal": {"add": {"cursor": [(6, 8), (7, 8)]}},
    "chart-line": {"cut": {"line": [(2, 2, 11, 8)]}},
    "power": {"cut": {"stem": [(5, 0, 6, 5)]}},
}


# Drawn from another icon, as (source, first column, past the last column):
# the columns outside are cleared. None at the moment.
DERIVED = {}


def polygons(d):
    """Rectilinear subpaths of an SVG path (M, H, V, L, h, v, l, m, Z)."""
    tokens = re.findall(r"[MmHhVvLlZz]|-?\d*\.?\d+", d)
    polys, cur, x, y, cmd, i = [], [], 0.0, 0.0, None, 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if cur:
                    polys.append(cur)
                    x, y = cur[0]
                cur = []
            continue
        if cmd in "Mm":
            nx, ny = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if cmd == "m":
                nx, ny = x + nx, y + ny
            if cur:
                polys.append(cur)
            cur = [(nx, ny)]
            x, y = nx, ny
            cmd = "l" if cmd == "m" else "L"
        elif cmd in "Ll":
            nx, ny = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if cmd == "l":
                nx, ny = x + nx, y + ny
            x, y = nx, ny
            cur.append((x, y))
        elif cmd in "Hh":
            v = float(tokens[i]); i += 1
            x = x + v if cmd == "h" else v
            cur.append((x, y))
        elif cmd in "Vv":
            v = float(tokens[i]); i += 1
            y = y + v if cmd == "v" else v
            cur.append((x, y))
        else:
            raise SystemExit("unsupported path command %r" % cmd)
    if cur:
        polys.append(cur)
    return polys


def raster(svg):
    """The 24x24 grid of an icon: rows of booleans, nonzero winding."""
    edges = []
    for d in re.findall(r'<path[^>]*\sd="([^"]+)"', svg):
        for poly in polygons(d):
            for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
                if x0 == x1 and y0 != y1:
                    edges.append((x0, y0, y1))
    for m in re.finditer(r'<rect[^>]*>', svg):
        a = dict(re.findall(r'(\w+)="([^"]+)"', m.group(0)))
        x, y, w, h = (float(a.get(k, 0)) for k in ("x", "y", "width", "height"))
        edges += [(x, y + h, y), (x + w, y, y + h)]
    if re.search(r"<(circle|ellipse|polygon|polyline|line)\b", svg):
        raise SystemExit("expected only paths and rects")
    grid = []
    for row in range(24):
        cy = row + 0.5
        line = []
        for col in range(24):
            cx = col + 0.5
            wind = 0
            for x, y0, y1 in edges:
                if x > cx and min(y0, y1) < cy < max(y0, y1):
                    wind += 1 if y1 > y0 else -1
            line.append(wind != 0)
        grid.append(line)
    return grid


def from_art(art):
    """A 12-cell drawing at 24 units: each cell two by two."""
    return [[art[r // 2][c // 2] == "#" for c in range(24)] for r in range(24)]


def halve(grid):
    # Every stroke is two units wide, so it covers exactly one odd unit:
    # sampling those keeps each stroke one cell wide, wherever it starts.
    return [[grid[r * 2 + 1][c * 2 + 1] for c in range(12)] for r in range(12)]


def rects(grid):
    """Runs along each row, merged down where the next rows repeat them."""
    n = len(grid)
    runs = []
    for r, line in enumerate(grid):
        c = 0
        while c < n:
            if line[c]:
                s = c
                while c < n and line[c]:
                    c += 1
                runs.append([s, r, c - s, 1])
            else:
                c += 1
    merged = []
    for run in runs:
        for m in merged:
            if m[0] == run[0] and m[2] == run[2] and m[1] + m[3] == run[1]:
                m[3] += 1
                break
        else:
            merged.append(list(run))
    return merged


def shift_of(grid):
    """Where the 24 grid's strokes start against the halved grid's cells,
    per axis: cell c covers units 2c+s and 2c+s+1. Pixelarticons put
    strokes on even units in some icons and odd ones in others."""
    small = halve(grid)
    best, out = -1, (0, 0)
    for sx in (0, 1):
        for sy in (0, 1):
            hits = sum(
                grid[v][u] == small[min(11, max(0, (v - sy) // 2))][min(11, max(0, (u - sx) // 2))]
                for v in range(24) for u in range(24))
            if hits > best:
                best, out = hits, (sx, sy)
    return out


def split(name, grid):
    """The icon's parts, each as a 24 grid and a 12 grid: the cut regions,
    "base" for the rest, and the added art."""
    spec = PARTS.get(name)
    if not spec:
        return None, None
    sx, sy = shift_of(grid)
    small = halve(grid)
    cuts = spec.get("cut", {})

    def owner(c, r):
        for part, regions in cuts.items():
            for x0, y0, x1, y1 in regions:
                if x0 <= c < x1 and y0 <= r < y1:
                    return part
        return "base"

    names = ["base"] + list(cuts) + list(spec.get("add", {}))
    big = {n: [[False] * 24 for _ in range(24)] for n in names}
    little = {n: [[False] * 12 for _ in range(12)] for n in names}
    # A unit belongs to the cell its stroke was sampled from. Strokes start
    # on either parity, so look at both cells a unit could fall in and take
    # the part of one that is drawn, a moving part over the base.
    for v in range(24):
        for u in range(24):
            if not grid[v][u]:
                continue
            seen = []
            for c in {min(11, max(0, (u - d) // 2)) for d in (sx, 1 - sx)}:
                for r in {min(11, max(0, (v - d) // 2)) for d in (sy, 1 - sy)}:
                    if small[r][c]:
                        seen.append(owner(c, r))
            moving = [o for o in seen if o != "base"]
            part = moving[0] if moving else "base" if seen else owner(
                min(11, max(0, (u - sx) // 2)), min(11, max(0, (v - sy) // 2)))
            big[part][v][u] = True
    for r in range(12):
        for c in range(12):
            if small[r][c]:
                little[owner(c, r)][r][c] = True
    ax, ay = spec.get("add-shift", (sx, sy))
    for part, cells in spec.get("add", {}).items():
        for c, r in cells:
            if small[r][c]:
                raise SystemExit("%s: added %s lands on the art at %d,%d" % (name, part, c, r))
            little[part][r][c] = True
            for v in (2 * r + ay, 2 * r + ay + 1):
                for u in (2 * c + ax, 2 * c + ax + 1):
                    if 0 <= u < 24 and 0 <= v < 24:
                        big[part][v][u] = True
    parts = {n: (big[n], little[n]) for n in names if any(any(line) for line in little[n])}
    return parts, (sx, sy)


def show(grid):
    return "\n".join("".join("#" if v else "." for v in line) for line in grid)


def main():
    local = lambda name: os.path.join(ROOT, "pixels", name + ".svg")
    pack = None
    if not all(os.path.exists(local(name)) for name in ICONS):
        with urllib.request.urlopen(TARBALL, timeout=30) as r:
            pack = tarfile.open(fileobj=io.BytesIO(r.read()))
    out = {}
    for name in ICONS:
        if pack:
            svg = pack.extractfile("package/svg/%s.svg" % name).read().decode()
            with open(local(name), "w") as f:
                f.write(svg)
        else:
            with open(local(name)) as f:
                svg = f.read()
        out[name] = raster(svg)
    for name, art in CUSTOM.items():
        out[name] = from_art(art)
    for name, (source, lo, hi) in DERIVED.items():
        out[name] = [[v and lo <= c < hi for c, v in enumerate(line)] for line in out[source]]
    if "--show" in sys.argv:
        for name, grid in out.items():
            print(name)
            print(show(grid))
            print(show(halve(grid)))
            parts, shift = split(name, grid)
            if parts:
                keys = list(parts)
                mark = lambda grids, v, u: next((chr(97 + i) for i, k in enumerate(keys) if grids[k][v][u]), ".")
                print("parts:", ", ".join("%s=%s" % (chr(97 + i), k) for i, k in enumerate(keys)), "shift", shift)
                big = {k: parts[k][0] for k in keys}
                little = {k: parts[k][1] for k in keys}
                for v in range(24):
                    tail = "".join(mark(little, v // 2, u) for u in range(12)) if v % 2 == 0 else ""
                    print("".join(mark(big, v, u) for u in range(24)) + "   " + tail)
            print()
        return
    lines = [
        ".pragma library",
        "",
        "// Generated by scripts/fetch-pixel-icons.py from Pixelarticons %s (MIT," % VERSION,
        "// https://pixelarticons.com), plus the server mark drawn there on the same grid.",
        "// Each icon is [x, y, width, height] rectangles: `g24` on the 24-unit grid,",
        "// `g12` on the same grid halved for small sizes. An icon that acts itself",
        "// out (Motion.js) also has `parts`, each with both grids, and `shift`: where",
        "// the 24 grid's strokes start against the 12 grid's cells, per axis.",
        "",
        "var icons = {",
    ]
    for name, grid in out.items():
        entry = "g24: %s, g12: %s" % (json.dumps(rects(grid)), json.dumps(rects(halve(grid))))
        parts, shift = split(name, grid)
        if parts:
            entry += ", shift: %s, parts: { %s }" % (json.dumps(list(shift)), ", ".join(
                "%s: { g24: %s, g12: %s }" % (json.dumps(k), json.dumps(rects(b)), json.dumps(rects(l)))
                for k, (b, l) in parts.items()))
        lines.append("  %s: { %s }," % (json.dumps(name), entry))
    lines[-1] = lines[-1].rstrip(",")
    lines += ["}", ""]
    with open(os.path.join(ROOT, "Pixels.js"), "w") as f:
        f.write("\n".join(lines))
    print("wrote Pixels.js with %d icons" % len(out))


if __name__ == "__main__":
    main()
