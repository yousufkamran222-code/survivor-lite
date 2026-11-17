#!/usr/bin/env python3
"""App icon art (generated, no outside assets): the white cell from the game
(lavender body, short cilia, cyan nucleus) on the dish, with a few germs.

  python3 tools/build_icon.py        -> assets/processed/icon/

Outputs
  icon_512.png                  full-bleed square: Play Store hi-res icon, project icon
  icon_192.png                  legacy launcher icon (Android export)
  adaptive_foreground_432.png   the cell only, inside the adaptive-icon safe zone
  adaptive_background_432.png   dish gradient + germs
  adaptive_monochrome_432.png   white silhouette (Android 13 themed icons)
Drawn 4x larger and scaled down (smooth edges). Colours match data/balance.json palette.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/processed/icon"
SS = 4  # supersampling
OUTLINE = (20, 10, 36, 255)
BODY = (244, 241, 255, 255)
BODY_EDGE = (205, 196, 236, 255)
NUC = (92, 225, 230, 255)
NUC_RIM = (40, 160, 178, 255)
GERMS = [(123, 211, 137), (241, 91, 181), (255, 159, 67), (255, 209, 102), (92, 225, 230)]


def radial(size, inner, outer, cx=0.5, cy=0.5, reach=0.75):
    im = Image.new("RGBA", (size, size))
    px = im.load()
    for y in range(size):
        for x in range(size):
            d = min(1.0, math.hypot(x / size - cx, y / size - cy) / reach)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * d) for i in range(3)) + (255,)
    return im


def germ(d, cx, cy, r, col, ss):
    d.ellipse([cx - r - 3 * ss, cy - r - 3 * ss, cx + r + 3 * ss, cy + r + 3 * ss], fill=OUTLINE)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (255,))
    d.ellipse([cx - r * 0.55, cy - r * 0.7, cx + r * 0.25, cy - r * 0.1], fill=(255, 255, 255, 60))
    for ex in (-0.32, 0.32):
        er = r * 0.17
        d.ellipse([cx + ex * r - er, cy + 0.05 * r - er, cx + ex * r + er, cy + 0.05 * r + er], fill=OUTLINE)


def cell(img, cx, cy, r, mono=False):
    """The player cell, drawn into img (RGBA) at supersampled coordinates."""
    s = img.size[0]
    d = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    # Cilia: short rounded strokes around the body.
    n = 18
    def capsule(x0, y0, x1, y1, w, col):
        d.line([x0, y0, x1, y1], fill=col, width=int(w))
        for x, y in ((x0, y0), (x1, y1)):
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=col)
    for k in range(n):
        a = math.tau * k / n + 0.08
        x0, y0 = cx + math.cos(a) * r * 0.96, cy + math.sin(a) * r * 0.96
        x1, y1 = cx + math.cos(a) * r * 1.24, cy + math.sin(a) * r * 1.24
        w = r * 0.1
        if not mono:
            capsule(x0, y0, x1, y1, w + r * 0.08, OUTLINE)
        capsule(x0, y0, x1, y1, w, white if mono else BODY)
    # Outline and body with a soft edge shade.
    o = r * 0.07
    if not mono:
        d.ellipse([cx - r - o, cy - r - o, cx + r + o, cy + r + o], fill=OUTLINE)
        body = radial(int(2 * r), BODY[:3], BODY_EDGE[:3], 0.42, 0.4, 0.62)
        mask = Image.new("L", body.size, 0)
        ImageDraw.Draw(mask).ellipse([0, 0, body.size[0] - 1, body.size[1] - 1], fill=255)
        img.paste(body, (int(cx - r), int(cy - r)), mask)
        # granules
        for gx, gy, gr in ((-0.45, 0.3, 0.07), (-0.2, 0.55, 0.05), (0.15, 0.6, 0.06), (-0.55, -0.1, 0.05)):
            d.ellipse([cx + gx * r - gr * r, cy + gy * r - gr * r, cx + gx * r + gr * r, cy + gy * r + gr * r], fill=(170, 160, 200, 255))
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=white)
    # Nucleus (up-right), rim, highlight.
    nx, ny, nr = cx + r * 0.2, cy - r * 0.14, r * 0.4
    if mono:
        d.ellipse([nx - nr, ny - nr, nx + nr, ny + nr], fill=(0, 0, 0, 0))
        hr = nr * 0.62
        d.ellipse([nx - hr, ny - hr, nx + hr, ny + hr], fill=white)
        return
    d.ellipse([nx - nr * 1.08, ny - nr * 1.08, nx + nr * 1.08, ny + nr * 1.08], fill=NUC_RIM)
    d.ellipse([nx - nr, ny - nr, nx + nr, ny + nr], fill=NUC)
    d.ellipse([nx - nr * 0.55, ny - nr * 0.62, nx - nr * 0.05, ny - nr * 0.12], fill=(235, 255, 255, 230))
    d.ellipse([nx + nr * 0.05, ny + nr * 0.05, nx + nr * 0.45, ny + nr * 0.45], fill=(70, 190, 205, 255))
    # Gloss on the body (top-left).
    gl = Image.new("RGBA", img.size, (255, 255, 255, 0))
    ImageDraw.Draw(gl).ellipse([cx - r * 0.7, cy - r * 0.78, cx - r * 0.2, cy - r * 0.45], fill=(255, 255, 255, 170))
    img.alpha_composite(gl.filter(ImageFilter.GaussianBlur(r * 0.03)))


def background(size, ring=True):
    s = size * SS
    img = radial(s, (64, 38, 120), (18, 10, 38), 0.5, 0.45, 0.8)
    d = ImageDraw.Draw(img)
    if ring:  # the dish rim
        m = s * 0.06
        d.ellipse([m, m, s - m, s - m], outline=(120, 90, 200, 110), width=int(s * 0.012))
    # Germs scattered towards the edges.
    spots = [(0.16, 0.2, 0.07, 0), (0.85, 0.16, 0.055, 1), (0.88, 0.8, 0.075, 2), (0.14, 0.82, 0.06, 3), (0.5, 0.08, 0.04, 4), (0.08, 0.5, 0.04, 1), (0.93, 0.48, 0.045, 0)]
    for x, y, r, c in spots:
        germ(d, x * s, y * s, r * s, GERMS[c], SS)
    return img


def glow(img, cx, cy, r):
    g = Image.new("RGBA", img.size, (160, 240, 255, 0))
    ImageDraw.Draw(g).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(160, 240, 255, 90))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(r * 0.35)))


def down(img, size):
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    # Full icon (512): background + glow + big cell.
    s = 512 * SS
    full = background(512)
    glow(full, s * 0.5, s * 0.52, s * 0.36)
    cell(full, s * 0.5, s * 0.52, s * 0.27)
    down(full, 512).save(f"{OUT}/icon_512.png")
    down(full, 192).save(f"{OUT}/icon_192.png")
    # Adaptive layers (432; the visible safe zone is the middle ~66%).
    a = 432 * SS
    bg = background(432, ring=False)
    down(bg, 432).save(f"{OUT}/adaptive_background_432.png")
    fg = Image.new("RGBA", (a, a), (0, 0, 0, 0))
    glow(fg, a * 0.5, a * 0.5, a * 0.3)
    cell(fg, a * 0.5, a * 0.5, a * 0.225)
    down(fg, 432).save(f"{OUT}/adaptive_foreground_432.png")
    mono = Image.new("RGBA", (a, a), (0, 0, 0, 0))
    cell(mono, a * 0.5, a * 0.5, a * 0.225, mono=True)
    down(mono, 432).save(f"{OUT}/adaptive_monochrome_432.png")
    print("icons ->", OUT)


if __name__ == "__main__":
    main()
