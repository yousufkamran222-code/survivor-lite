#!/usr/bin/env python3
"""Rebuild everything in assets/processed/ from code (and assets/raw/ later).

Synthesises all sound effects (sfxr-style: oscillators, pitch sweeps, noise
and envelopes) and draws the tiled background, so there are no licensing
questions. Output is deterministic.

Usage:  python3 tools/build_assets.py
Needs:  numpy, pillow
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "processed" / "sfx"
RATE = 22050
RNG = np.random.default_rng(1234)


def _t(dur: float) -> np.ndarray:
    return np.arange(int(RATE * dur)) / RATE


def osc(freq_start: float, freq_end: float, dur: float, shape: str = "square") -> np.ndarray:
    t = _t(dur)
    freq = np.geomspace(max(freq_start, 1), max(freq_end, 1), t.size)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    if shape == "sine":
        return np.sin(phase)
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    return np.sign(np.sin(phase)) * 0.6


def noise(dur: float, lowpass: float = 1.0) -> np.ndarray:
    n = RNG.uniform(-1, 1, int(RATE * dur))
    if lowpass < 1.0:
        out = np.empty_like(n)
        acc = 0.0
        for i, v in enumerate(n):
            acc += lowpass * (v - acc)
            out[i] = acc
        n = out / max(np.abs(out).max(), 1e-6)
    return n


def env(x: np.ndarray, attack: float = 0.005, decay_pow: float = 2.0) -> np.ndarray:
    n = x.size
    a = max(1, int(RATE * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[a:] = np.linspace(1, 0, n - a) ** decay_pow
    return x * e


def mix(*parts: np.ndarray) -> np.ndarray:
    n = max(p.size for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: p.size] += p
    return out


def seq(*parts: np.ndarray) -> np.ndarray:
    return np.concatenate(parts)


def write(name: str, x: np.ndarray, gain: float = 0.8) -> None:
    peak = max(np.abs(x).max(), 1e-6)
    x = np.clip(x / peak * gain, -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    with wave.open(str(SFX_DIR / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"wrote {name}.wav ({x.size / RATE:.2f}s)")


def build_sfx() -> None:
    write("shoot", env(osc(1400, 500, 0.08, "square"), decay_pow=1.5), 0.5)
    write("hit", env(mix(osc(300, 120, 0.06, "square"), noise(0.06) * 0.4)), 0.5)
    write("kill", env(mix(osc(520, 90, 0.16, "tri"), noise(0.16, 0.3) * 0.6), decay_pow=2.5), 0.7)
    write("pickup", env(osc(900, 1700, 0.07, "sine"), decay_pow=1.2), 0.5)
    write("level_up", seq(*[env(osc(f, f, 0.09, "square"), decay_pow=0.8) for f in (523, 659, 784, 1047)]), 0.6)
    write("hurt", env(mix(osc(220, 70, 0.22, "saw"), noise(0.22, 0.2) * 0.8), decay_pow=1.6), 0.8)
    write("nova", env(mix(osc(160, 40, 0.35, "sine"), noise(0.35, 0.08) * 0.7), attack=0.01, decay_pow=1.8), 0.8)
    write("chain", env(mix(noise(0.14, 0.9), osc(2200, 900, 0.14, "saw") * 0.4), decay_pow=1.3), 0.5)
    write("death", env(mix(osc(400, 40, 0.9, "saw"), noise(0.9, 0.05) * 0.8), attack=0.01, decay_pow=1.4), 0.8)
    write("boss", env(mix(osc(70, 50, 1.2, "saw"), osc(105, 75, 1.2, "square") * 0.5), attack=0.15, decay_pow=1.2), 0.8)
    write("click", env(osc(1000, 1000, 0.03, "sine")), 0.4)
    write("dash", env(mix(noise(0.18, 0.25), osc(900, 300, 0.18, "sine") * 0.5), attack=0.01, decay_pow=1.5), 0.6)
    write("elite", seq(env(osc(220, 220, 0.18, "square"), decay_pow=0.6), env(osc(165, 165, 0.3, "square"), decay_pow=0.8)), 0.6)
    write("vacuum", env(mix(osc(200, 1600, 0.6, "sine"), noise(0.6, 0.15) * 0.4), attack=0.05, decay_pow=0.7), 0.6)
    write("heal", seq(*[env(osc(f, f, 0.1, "sine"), decay_pow=1.0) for f in (660, 880, 1320)]), 0.5)
    write("bomb", env(mix(osc(120, 30, 0.9, "sine"), noise(0.9, 0.04) * 1.2), attack=0.005, decay_pow=1.6), 0.9)
    write("chest", seq(*[env(osc(f, f, 0.07, "tri"), decay_pow=0.9) for f in (392, 494, 587, 784, 988)]), 0.6)
    write("claim", seq(env(osc(330, 660, 0.12, "tri"), decay_pow=0.8), env(osc(660, 990, 0.16, "sine"), decay_pow=1.2)), 0.6)
    write("convert", env(mix(osc(300, 900, 0.22, "tri"), osc(450, 1350, 0.22, "sine") * 0.5), attack=0.01, decay_pow=1.1), 0.5)
    # Meta shop: a bright rising chime with a sparkle tail; a soft low "nope".
    write("upgrade", mix(seq(*[env(osc(f, f, 0.07, "tri"), decay_pow=0.9) for f in (523, 784, 1047)], env(osc(1568, 2093, 0.28, "sine"), decay_pow=1.4)), np.pad(env(noise(0.2, 0.6), decay_pow=2.5) * 0.25, (int(0.21 * RATE), 0))), 0.6)
    write("deny", seq(env(osc(196, 180, 0.07, "square"), decay_pow=0.7), env(osc(147, 130, 0.12, "square"), decay_pow=1.0)), 0.35)
    write("evolve", mix(*[env(osc(f, f * 2, 0.9, "saw"), attack=0.02, decay_pow=1.2) * 0.4 for f in (262, 330, 392, 523)]), 0.8)
    # Added later: keep new sounds at the end so the shared noise RNG doesn't
    # change the sounds above.
    write("kill2", env(mix(osc(640, 150, 0.14, "tri"), noise(0.14, 0.4) * 0.5), decay_pow=2.2), 0.65)
    # Low-HP heartbeat: "lub-dub", two soft low thumps (sine only).
    write("heartbeat", seq(env(osc(95, 48, 0.13, "sine"), attack=0.004, decay_pow=2.4), np.zeros(int(0.08 * RATE)), env(osc(85, 42, 0.11, "sine"), attack=0.004, decay_pow=2.6) * 0.7, np.zeros(int(0.05 * RATE))), 0.9)


def build_background(size: int = 512, bg="#150e2b", dots="#231845", cells="#1d1439", rims="#2b2056") -> None:
    """Seamless 512px tile drawn under the world: an agar floor with soft
    cells (a lighter rim, a darker inside), faint dots and fine speckle."""
    from PIL import ImageFilter
    rng = np.random.default_rng(99)
    scale = 4  # supersample for smooth edges
    img = Image.new("RGB", (size * scale, size * scale), bg)
    d = ImageDraw.Draw(img)

    def blob(x, y, r, col, width=0):
        for ox in (-size, 0, size):  # wrap so the tile is seamless
            for oy in (-size, 0, size):
                cx, cy = (x + ox) * scale, (y + oy) * scale
                box = [cx - r * scale, cy - r * scale, cx + r * scale, cy + r * scale]
                if width:
                    d.ellipse(box, outline=col, width=int(width * scale))
                else:
                    d.ellipse(box, fill=col)

    for _ in range(7):
        x, y, r = rng.uniform(0, size), rng.uniform(0, size), rng.uniform(20, 48)
        blob(x, y, r, cells)
        blob(x, y, r, rims, width=2.2)
        blob(x + r * 0.25, y - r * 0.2, r * 0.22, rims)  # a nucleus
    for _ in range(30):
        blob(rng.uniform(0, size), rng.uniform(0, size), rng.uniform(2.0, 4.5), dots)
    img = img.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.6))
    # Fine agar speckle (low contrast, seamless by construction).
    arr = np.asarray(img).astype(np.int16)
    arr += rng.integers(-3, 4, size=(size, size, 1)).astype(np.int16)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    out = ROOT / "assets" / "processed" / "bg_tile.png"
    img.save(out, optimize=True)
    print(f"wrote {out.name}")


if __name__ == "__main__":
    build_sfx()
    build_background()
