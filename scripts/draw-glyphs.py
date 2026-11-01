#!/usr/bin/env python3
"""
Draw the panel's server glyphs and write Glyphs.js.

Drawn the way Batteries draws devices: one solid silhouette with fine details
cut out of it. Each glyph is built here from plain shapes on a 48-unit grid
and filled even-odd, so a shape inside another cuts it and a shape inside a
cut fills again (a drive bay in the chassis, the spindle in the platter).
Shapes must never overlap, or the overlap flips. Run from the repo root:

    python3 scripts/draw-glyphs.py
"""

import json
import math
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def n(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def rrect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    return ("M%s %sH%sA%s %s 0 0 1 %s %sV%sA%s %s 0 0 1 %s %sH%sA%s %s 0 0 1 %s %sV%sA%s %s 0 0 1 %s %sZ" % (
        n(x + r), n(y), n(x + w - r), n(r), n(r), n(x + w), n(y + r), n(y + h - r), n(r), n(r), n(x + w - r), n(y + h),
        n(x + r), n(r), n(r), n(x), n(y + h - r), n(y + r), n(r), n(r), n(x + r), n(y)))


def circle(cx, cy, r):
    return "M%s %sA%s %s 0 1 1 %s %sA%s %s 0 1 1 %s %sZ" % (
        n(cx - r), n(cy), n(r), n(r), n(cx + r), n(cy), n(r), n(r), n(cx - r), n(cy))


def capsule(x1, y1, x2, y2, w):
    # A line with round ends, from (x1, y1) to (x2, y2), `w` wide.
    length = math.hypot(x2 - x1, y2 - y1)
    r = w / 2
    nx, ny = -(y2 - y1) / length * r, (x2 - x1) / length * r
    return "M%s %sL%s %sA%s %s 0 0 0 %s %sL%s %sA%s %s 0 0 0 %s %sZ" % (
        n(x1 + nx), n(y1 + ny), n(x2 + nx), n(y2 + ny), n(r), n(r), n(x2 - nx), n(y2 - ny),
        n(x1 - nx), n(y1 - ny), n(r), n(r), n(x1 + nx), n(y1 + ny))


def server():
    # Three rack units from the front, like the bar's server mark: each with
    # its power and status lights, a drive slot and a vent.
    out = []
    for top in (7.2, 19.0, 30.8):
        out.append(rrect(3, top, 42, 10, 2))
        out.append(circle(7.6, top + 5, 1.1))
        out.append(circle(11.4, top + 5, 1.1))
        out.append(rrect(16, top + 4.55, 14.5, 0.9, 0.45))
        for i in range(5):
            out.append(rrect(33.8 + i * 1.95, top + 2.5, 0.85, 5.0, 0.42))
    return out


def cpu():
    # A processor from above: the package with its pins on all four sides,
    # the lid's edge and the corner mark.
    out = [rrect(12, 12, 24, 24, 2.4)]
    for i in range(4):
        p = 15.3 + i * 5.2
        out += [rrect(p, 7, 1.8, 4.2, 0.5), rrect(p, 36.8, 1.8, 4.2, 0.5),
                rrect(7, p, 4.2, 1.8, 0.5), rrect(36.8, p, 4.2, 1.8, 0.5)]
    out += [rrect(16.4, 16.4, 15.2, 15.2, 1.4), rrect(17.3, 17.3, 13.4, 13.4, 0.9), circle(20.3, 20.3, 0.95)]
    return out


def memory():
    # A memory stick: the board with its key notch, four chips, and the
    # contacts along the bottom edge.
    out = ["M4.2 14H43.8A1.2 1.2 0 0 1 45 15.2V32H22.4V29.6H19.6V32H3V15.2A1.2 1.2 0 0 1 4.2 14Z"]
    x = 6.6
    for _ in range(4):
        out.append(rrect(x, 16.6, 7.6, 8.4, 0.9))
        out.append(rrect(x + 0.9, 17.5, 5.8, 6.6, 0.45))
        x += 9.0
    for i in range(17):
        cx = 5.2 + i * 2.25
        if 18.6 < cx < 23.2:
            continue
        out.append(rrect(cx, 27.6, 0.85, 3.2, 0.42))
    return out


def disk():
    # A hard drive from above: the platter with its spindle and the arm over
    # it, the label below, a screw in each corner.
    return [
        rrect(9, 3, 30, 42, 2.6),
        circle(24, 18.5, 11.6), circle(24, 18.5, 2.2), circle(24, 18.5, 0.8),
        capsule(31.1, 25.9, 26.4, 21.7, 1.8),
        rrect(14, 33.4, 20, 6.6, 1.0), rrect(14.9, 34.3, 18.2, 4.8, 0.55),
        circle(12.2, 6.2, 0.85), circle(35.8, 6.2, 0.85), circle(12.2, 41.8, 0.85), circle(35.8, 41.8, 0.85),
    ]


def thermometer():
    # A thermometer: the stem with its scale and the line up its middle, the
    # bulb with a ring inside.
    return [
        "M19.5 6.5A4.5 4.5 0 0 1 28.5 6.5V29.21A9 9 0 1 1 19.5 29.21Z",
        rrect(23.55, 7, 0.9, 22.9, 0.45),
        rrect(25.6, 10, 1.8, 0.85, 0.42), rrect(25.6, 14, 1.8, 0.85, 0.42),
        rrect(25.6, 18, 1.8, 0.85, 0.42), rrect(25.6, 22, 1.8, 0.85, 0.42),
        rrect(25.6, 26, 1.8, 0.85, 0.42),
        circle(24, 37, 6.2), circle(24, 37, 5.3),
    ]


# Arcs only list their end points, so a glyph whose outline bulges past
# them names its extent here.
INK = {
    "thermometer": [15, 2, 33, 46],
}

GLYPHS = {
    "server": server,
    "cpu": cpu,
    "memory": memory,
    "disk": disk,
    "thermometer": thermometer,
}


def bounds(path):
    xs, ys = [], []
    for cmd in re.finditer(r"([MLHVCQAZ])([^MLHVCQAZ]*)", path):
        c, args = cmd.group(1), [float(v) for v in re.findall(r"-?\d*\.?\d+", cmd.group(2))]
        if c in "ML":
            xs += args[0::2]; ys += args[1::2]
        elif c == "H":
            xs += args
        elif c == "V":
            ys += args
        elif c in "CQ":
            xs += args[0::2]; ys += args[1::2]
        elif c == "A":
            xs.append(args[5]); ys.append(args[6])
    return xs, ys


def main():
    glyphs = {}
    for name, draw in GLYPHS.items():
        parts = draw()
        path = " ".join(parts)
        # The points each part moves or draws to, control points included:
        # close enough to the drawn extent for these shapes.
        xs, ys = bounds(path)
        ink = INK.get(name) or [min(xs), min(ys), max(xs), max(ys)]
        glyphs[name] = {"ink": [round(v, 3) for v in ink], "path": path}

    lines = [
        ".pragma library",
        "",
        "// Generated by scripts/draw-glyphs.py: the panel's server glyphs, solid",
        "// with details cut out, on a 48-unit grid. Fill them odd-even. `ink` is",
        "// each drawing's extent as [left, top, right, bottom].",
        "",
        "var glyphs = {",
    ]
    lines += ["  %s: %s," % (json.dumps(k), json.dumps(v)) for k, v in glyphs.items()]
    lines[-1] = lines[-1].rstrip(",")
    lines += ["}", ""]
    with open(os.path.join(ROOT, "Glyphs.js"), "w") as f:
        f.write("\n".join(lines))

    # A preview sheet, for drawing new glyphs.
    cells = []
    for name, g in glyphs.items():
        x0, y0, x1, y1 = g["ink"]
        cells.append('<figure><svg viewBox="%s %s %s %s"><path fill-rule="evenodd" d="%s"/></svg><figcaption>%s</figcaption></figure>' % (
            n(x0), n(y0), n(x1 - x0), n(y1 - y0), g["path"], name))
    with open("/tmp/glyphs-preview.html", "w") as f:
        f.write("".join(cells))
    print("wrote Glyphs.js with %d glyphs" % len(glyphs))


if __name__ == "__main__":
    main()
