#!/usr/bin/env python3
"""Store cover art: the game title (Lilita One, the in-game display font, gold
with a thick dark outline and a soft drop shadow) over a rendered key-art frame.

Usage (repo root):
  python3 tools/footage/cover.py FRAME.png OUT.png WIDTH HEIGHT [--title-y 0.2] [--size 0.16]

FRAME is scaled to cover WIDTHxHEIGHT (centre crop, Lanczos), the title is
centred at title-y (share of the height) with a font size of `size` x width.
A gentle dark gradient sits behind the title so it reads on any frame (no
border, no blur: CrazyGames cover rules allow only the title as text).
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "assets/raw/lilita_one/LilitaOne-Regular.ttf"
GOLD = (255, 209, 102)
OUTLINE = (20, 10, 36)
TITLE = "PETRI PANIC"


def cover(frame, out, w, h, title_y=0.2, size=0.16):
    im = Image.open(frame).convert("RGB")
    k = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    x0 = (im.width - w) // 2
    y0 = (im.height - h) // 2
    im = im.crop((x0, y0, x0 + w, y0 + h)).convert("RGBA")

    # Soft dark band behind the title (a vertical gradient, strongest at the title).
    band = Image.new("L", (w, h), 0)
    bd = ImageDraw.Draw(band)
    cy = int(h * title_y)
    reach = int(h * 0.22)
    for y in range(max(0, cy - reach), min(h, cy + reach)):
        a = 1.0 - abs(y - cy) / reach
        bd.line([(0, y), (w, y)], fill=int(150 * a * a))
    dark = Image.new("RGBA", (w, h), (10, 5, 22, 255))
    im = Image.composite(dark, im, band)

    fs = int(w * size)
    font = ImageFont.truetype(FONT, fs)
    # Shrink to fit 90% of the width.
    while font.getlength(TITLE) > w * 0.9 and fs > 10:
        fs -= 2
        font = ImageFont.truetype(FONT, fs)
    tw = font.getlength(TITLE)
    tx = (w - tw) / 2
    ty = cy - fs * 0.62
    ow = max(4, fs // 9)

    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((tx, ty + fs * 0.08), TITLE, font=font, fill=(0, 0, 0, 170),
                                stroke_width=ow, stroke_fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(fs * 0.05))
    im = Image.alpha_composite(im, shadow)
    txt = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(txt)
    d.text((tx, ty), TITLE, font=font, fill=GOLD + (255,), stroke_width=ow, stroke_fill=OUTLINE + (255,))
    # A light band on the top half of the letters (the in-game gloss).
    hi = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(hi).text((tx, ty), TITLE, font=font, fill=(255, 240, 200, 255))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle([0, 0, w, int(ty + fs * 0.55)], fill=110)
    hi.putalpha(Image.composite(hi.getchannel("A"), Image.new("L", (w, h), 0), mask))
    im = Image.alpha_composite(im, txt)
    im = Image.alpha_composite(im, hi)
    im.convert("RGB").save(out, quality=95)
    print(out, w, h, "font", fs)


if __name__ == "__main__":
    a = sys.argv[1:]
    ty = float(a[a.index("--title-y") + 1]) if "--title-y" in a else 0.2
    sz = float(a[a.index("--size") + 1]) if "--size" in a else 0.16
    cover(a[0], a[1], int(a[2]), int(a[3]), ty, sz)
