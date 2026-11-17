#!/usr/bin/env python3
"""Play Store listing art from rendered game frames (tools/footage/showcase.gd).

  python3 tools/build_store_art.py shots SPEC.json OUT_DIR
      SPEC: [{"frame": "path.png", "caption": "EVOLVE YOUR WEAPONS"}, ...]
      -> OUT_DIR/screenshot_1.png ... : 1080x1920 (9:16), a caption in the
         display font over the dish colours, the frame below it with rounded
         corners and a dark outline.
  python3 tools/build_store_art.py feature FRAME.png OUT.png
      -> 1024x500 feature graphic: the frame, cropped, with the title.

Outputs are big PNGs: they go to build/store_kit/play/ (not committed).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "assets/raw/lilita_one/LilitaOne-Regular.ttf"
GOLD = (255, 209, 102)
OUTLINE = (20, 10, 36)
BG_TOP = (52, 30, 100)
BG_BOT = (18, 10, 38)


def vgrad(w, h, a, b):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        k = y / max(h - 1, 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3)))
    return im


def fit_text(txt, max_w, size):
    while size > 20:
        f = ImageFont.truetype(FONT, size)
        if f.getlength(txt) <= max_w:
            return f
        size -= 4
    return ImageFont.truetype(FONT, size)


def title(img, txt, cy, size, max_w):
    w, h = img.size
    f = fit_text(txt, max_w, size)
    tw = f.getlength(txt)
    x = (w - tw) / 2
    y = cy - f.size * 0.62
    ow = max(4, f.size // 9)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((x, y + f.size * 0.08), txt, font=f, fill=(0, 0, 0, 160), stroke_width=ow, stroke_fill=(0, 0, 0, 160))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(f.size * 0.05)))
    ImageDraw.Draw(img).text((x, y), txt, font=f, fill=GOLD + (255,), stroke_width=ow, stroke_fill=OUTLINE + (255,))


def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], r, fill=255)
    out = im.convert("RGBA")
    out.putalpha(m)
    return out


def screenshot(frame, caption, out):
    W, H = 1080, 1920
    img = vgrad(W, H, BG_TOP, BG_BOT).convert("RGBA")
    fr = Image.open(frame).convert("RGB")
    # The frame below the caption: at most 82% size (smaller if a wide or tall
    # frame would not fit under the caption), centred, rounded, outlined.
    k = min(0.82, (W - 60) / fr.width, (H - 300) / fr.height)
    fw, fh = int(fr.width * k), int(fr.height * k)
    fr = fr.resize((fw, fh), Image.LANCZOS)
    x0, y0 = (W - fw) // 2, H - fh - 70
    border = Image.new("RGBA", (fw + 16, fh + 16), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle([0, 0, fw + 15, fh + 15], 44, fill=OUTLINE + (255,))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x0 - 20, y0 - 20, x0 + fw + 20, y0 + fh + 20], 60, fill=(120, 80, 220, 120))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(26)))
    img.alpha_composite(border, (x0 - 8, y0 - 8))
    img.alpha_composite(rounded(fr, 38), (x0, y0))
    title(img, caption, (y0 - 8) // 2 + 6, 118, W - 90)
    img.convert("RGB").save(out)
    print(out)


def feature(frame, out):
    W, H = 1024, 500
    fr = Image.open(frame).convert("RGB")
    k = max(W / fr.width, H / fr.height) * 1.15  # a little zoom: the cell bigger
    fr = fr.resize((int(fr.width * k), int(fr.height * k)), Image.LANCZOS)
    x0 = (fr.width - W) // 2
    # The camera follows the player, so the cell is at the frame's centre: put
    # it at 64% of the banner height, under the title (clamped to the frame).
    y0 = max(0, min(fr.height - H, int(fr.height / 2 - H * 0.64)))
    img = fr.crop((x0, y0, x0 + W, y0 + H)).convert("RGBA")
    shade = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(shade)
    for y in range(H):
        a = max(0.0, 1.0 - abs(y - H * 0.24) / (H * 0.3))
        d.line([(0, y), (W, y)], fill=int(130 * a))
    img = Image.composite(Image.new("RGBA", (W, H), (10, 5, 22, 255)), img, shade)
    title(img, "PETRI PANIC", H * 0.24, 118, W * 0.8)
    img.convert("RGB").save(out)
    print(out)


USAGE = "usage: build_store_art.py shots SPEC.json OUT_DIR | feature FRAME.png OUT.png"

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd not in ("shots", "feature") or len(sys.argv) != 4:
        sys.exit(USAGE)
    if cmd == "shots":
        spec = json.load(open(sys.argv[2]))
        os.makedirs(sys.argv[3], exist_ok=True)
        for i, s in enumerate(spec, 1):
            screenshot(s["frame"], s["caption"], os.path.join(sys.argv[3], f"screenshot_{i}.png"))
    else:
        feature(sys.argv[2], sys.argv[3])
