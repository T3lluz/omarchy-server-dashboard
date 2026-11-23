#!/usr/bin/env python3
"""
Give the bundled Monocraft a zero-width space (U+200B) and a family name of
its own.

The panel marks where a long name may break with a zero-width space
(Model.breakable). Monocraft has no such glyph, so Qt took it from a fallback
font, and that font's taller line height opened a wider gap under every line
that broke there. An empty glyph with no advance keeps the whole line in
Monocraft.

The other plugins bundle Monocraft too, and every copy loads into the one
shell process. Under one family name Qt draws whichever copy it registered
first, which may lack the glyph, so ours is "Monocraft Server Dashboard".
The licence (SIL OFL 1.1, assets/fonts/OFL.txt) reserves no font name, so a
modified copy may be named either way. Needs fontTools. Run from the repo
root after updating the fonts; running it twice changes nothing:

    python3 scripts/patch-font.py
"""

import os
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

sys.dont_write_bytecode = True

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONTS = ["assets/fonts/Monocraft.ttf", "assets/fonts/Monocraft-Bold.ttf"]
ZWSP = 0x200B
NAME = "uni200B"
FAMILY = "Monocraft Server Dashboard"


def rename(font):
    """The family, full and PostScript names, for both weights."""
    names = font["name"]
    style = names.getDebugName(2) or "Regular"
    full = FAMILY if style == "Regular" else FAMILY + " " + style
    changed = False
    postscript = FAMILY.replace(" ", "") + "-" + style.replace(" ", "")
    for record in names.names:
        value = {1: FAMILY, 4: full, 6: postscript}.get(record.nameID)
        if value is not None and record.toUnicode() != value:
            record.string = value
            changed = True
    return changed


def patch(path):
    font = TTFont(path)
    changed = rename(font)
    if ZWSP in font.getBestCmap():
        if changed:
            font.save(path)
        return changed
    order = font.getGlyphOrder()
    if NAME not in order:
        font.setGlyphOrder(order + [NAME])
        font["glyf"][NAME] = TTGlyphPen(None).glyph()
        font["hmtx"][NAME] = (0, 0)
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap[ZWSP] = NAME
    font.save(path)
    return True


def main():
    for rel in FONTS:
        path = os.path.join(ROOT, rel)
        print(("patched " if patch(path) else "already patched: ") + rel)


if __name__ == "__main__":
    main()
