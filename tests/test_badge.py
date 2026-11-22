"""bin/badge: the pixel picture a notification carries."""

import importlib.machinery
import importlib.util
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.dont_write_bytecode = True
SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "badge")
loader = importlib.machinery.SourceFileLoader("badge", SCRIPT)
spec = importlib.util.spec_from_loader("badge", loader)
badge = importlib.util.module_from_spec(spec)
loader.exec_module(badge)

TONE = (224, 108, 117)


def pixel(rows, x, y):
    return tuple(rows[y][x * 4:x * 4 + 4])


class BadgeTest(unittest.TestCase):
    def test_icons_used_by_alerts_are_found(self):
        for name in ("server", "database", "package", "warning-diamond"):
            icon = badge.pixel_icon(name)
            self.assertIsNotNone(icon, name)
            self.assertTrue(icon["g24"] and icon["g12"])

    def test_tile_is_the_tone_faintly_and_icon_solid(self):
        for size in (40, 46, 74):
            rows = badge.badge_pixels(size, badge.pixel_icon("server"), TONE, "cross")
            self.assertEqual(len(rows), size)
            self.assertEqual(len(rows[0]), size * 4)
            corner = pixel(rows, 0, 0)
            self.assertEqual(corner[:3], TONE)
            self.assertEqual(corner[3], round(0.14 * 255))
            # Only two alphas: the tile and solid ink; nothing in between, so
            # nothing was smoothed.
            alphas = {pixel(rows, x, y)[3] for y in range(size) for x in range(size)}
            self.assertEqual(alphas, {36, 255}, size)

    def test_strokes_are_whole_units(self):
        # 46 at 1.25: a unit of 2, the icon on the 24 grid at a pixel a cell.
        # 74 at 2: a unit of 3, the 12 grid at 3. A cross's arm is a unit wide.
        for size, u in ((46, 2), (74, 3)):
            rows = badge.badge_pixels(size, None, TONE, "cross")
            top = (size - 20 * u) // 2 + 14 * u
            mx = (size - 5 * u) // 2
            my = top + (6 * u - 5 * u) // 2
            for dx in range(u):
                for dy in range(u):
                    self.assertEqual(pixel(rows, mx + dx, my + dy)[3], 255)
            self.assertEqual(pixel(rows, mx + u, my)[3], 36)

    def test_meter_fills_to_the_level(self):
        u = 2
        size = 46
        top = (size - 20 * u) // 2 + 14 * u
        bx = (size - 18 * u) // 2
        for level, solid in ((0, 0), (20, 1), (60, 3), (100, 5)):
            rows = badge.badge_pixels(size, None, TONE, "meter:%d" % level)
            cells = [pixel(rows, bx + 2 * u + n * 3 * u, top + 2 * u)[3] == 255 for n in range(5)]
            self.assertEqual(sum(cells), solid, level)

    def test_no_mark_centres_the_icon(self):
        rows = badge.badge_pixels(46, badge.pixel_icon("server"), TONE, "none")
        ink = [y for y in range(46) if any(rows[y][x * 4 + 3] == 255 for x in range(46))]
        self.assertAlmostEqual((ink[0] + ink[-1]) / 2, 23, delta=2)

    def test_writes_a_png_of_the_size_asked(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "alerts", "server.png")
            run = subprocess.run([sys.executable, "-B", SCRIPT, out, "46", "server", "#e06c75", "cross"])
            self.assertEqual(run.returncode, 0)
            data = open(out, "rb").read()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            w, h = struct.unpack(">II", data[16:24])
            self.assertEqual((w, h), (46, 46))
            self.assertEqual(sorted(os.listdir(os.path.dirname(out))), ["server.png"])
            self.assertEqual(len(zlib.decompress(data[41:-16])), 46 * (46 * 4 + 1))

    def test_bad_arguments(self):
        self.assertEqual(subprocess.run([sys.executable, "-B", SCRIPT], capture_output=True).returncode, 2)
        self.assertEqual(badge.hex_rgb("#ff8800aa"[:7]), (255, 136, 0))
        self.assertEqual(badge.hex_rgb("#80ff8800"), (255, 136, 0))
        self.assertEqual(badge.hex_rgb("nope"), (255, 255, 255))


if __name__ == "__main__":
    unittest.main()
