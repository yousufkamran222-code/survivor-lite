#!/usr/bin/env python3
"""Redraws K and X in Kenney Future Narrow (CC0), whose stylised K and X look
like H ("BACK" read "BACH", "MAX" read "MAH"). Same 512x640 grid and ~128-unit
strokes as the rest of the font. Lowercase k/x (separate glyphs) get the same
shapes (the font is all caps).

    python3 tools/patch_font.py   (needs fonttools: pip install fonttools)

Input:  assets/raw/kenney_fonts/Kenney Future Narrow.ttf
Output: assets/raw/kenney_fonts/Kenney Future Narrow KX.ttf
"""
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

SRC = "assets/raw/kenney_fonts/Kenney Future Narrow.ttf"
DST = "assets/raw/kenney_fonts/Kenney Future Narrow KX.ttf"


def clockwise(poly):
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]))
    return poly if area < 0 else list(reversed(poly))  # TrueType outer contours run clockwise


def glyph(polys, font):
    pen = TTGlyphPen(font.getGlyphSet())
    for poly in polys:
        poly = clockwise(poly)
        pen.moveTo(poly[0])
        for p in poly[1:]:
            pen.lineTo(p)
        pen.closePath()
    return pen.glyph()


K = [
    [(0, 0), (0, 640), (128, 640), (128, 0)],          # stem
    [(128, 256), (128, 448), (320, 640), (512, 640)],  # upper arm
    [(128, 384), (128, 192), (320, 0), (512, 0)],      # lower leg
]
X = [
    [(0, 0), (155, 0), (512, 640), (357, 640)],
    [(512, 0), (357, 0), (0, 640), (155, 640)],
]

font = TTFont(SRC)
cmap = font.getBestCmap()
for ch, polys in (("K", K), ("X", X), ("k", K), ("x", X)):
    name = cmap[ord(ch)]
    font["glyf"][name] = glyph(polys, font)
    font["hmtx"][name] = (font["hmtx"][name][0], 0)
font.save(DST)
print("wrote", DST)
