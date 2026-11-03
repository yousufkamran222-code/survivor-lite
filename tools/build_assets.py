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


# ---------------------------------------------------------------- music
# Generated loops (no licensing): a calm menu loop, and a run loop in two
# layers that play in sync. The game fades the "drive" layer in with the
# run's intensity. Own RNG, so the sound effects above never change.
MUSIC_DIR = ROOT / "assets" / "processed" / "music"
MRNG = np.random.default_rng(4321)
PROG = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]  # Am F C G (MIDI)


def hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def tone(freq: float, dur: float, shape: str = "sine", attack: float = 0.01, decay: float = 4.0) -> np.ndarray:
    t = _t(dur)
    ph = 2 * np.pi * freq * t
    if shape == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(ph))
    elif shape == "soft":  # rounded square for the bass
        w = np.tanh(3 * np.sin(ph)) * 0.7
    else:
        w = np.sin(ph)
    a = max(1, int(RATE * attack))
    e = np.exp(-decay * t)
    e[:a] *= np.linspace(0, 1, a)
    return w * e


def pad(freqs, dur: float) -> np.ndarray:
    t = _t(dur)
    out = np.zeros(t.size)
    for f in freqs:
        for det in (0.997, 1.003):
            out += np.sin(2 * np.pi * f * det * t) + 0.25 * (2 / np.pi) * np.arcsin(np.sin(2 * np.pi * f * 2 * det * t))
    fade = np.minimum(1, np.minimum(t / 0.5, (dur - t) / 0.5))
    return out * np.clip(fade, 0, 1) / (len(freqs) * 2)


def place(buf: np.ndarray, x: np.ndarray, at: float, gain: float = 1.0) -> None:
    """Adds x into the loop buffer at time `at`, wrapping around the end so
    the loop has no click."""
    i = int(at * RATE) % buf.size
    end = i + x.size
    if end <= buf.size:
        buf[i:end] += x * gain
    else:
        k = buf.size - i
        buf[i:] += x[:k] * gain
        buf[: x.size - k] += x[k:] * gain


def write_music(name: str, x: np.ndarray, gain: float = 0.7) -> None:
    peak = max(np.abs(x).max(), 1e-6)
    x = np.clip(x / peak * gain, -1, 1)
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    with wave.open(str(MUSIC_DIR / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print(f"wrote music/{name}.wav ({x.size / RATE:.2f}s)")


def build_music() -> None:
    # Menu: 90 BPM, 8 bars. Soft pad, slow arpeggio, a few bubble blips.
    beat = 60 / 90
    bars = 8
    buf = np.zeros(int(RATE * beat * 4 * bars))
    for b in range(bars):
        chord = PROG[(b // 2) % 4]
        t0 = b * 4 * beat
        if b % 2 == 0:
            place(buf, pad([hz(n - 12) for n in chord], beat * 8 + 0.6), t0, 0.55)
        for q in range(4):
            n = chord[(q + b) % 3] + (12 if q % 2 else 0)
            place(buf, tone(hz(n), 1.2, "tri", 0.005, 3.5), t0 + q * beat, 0.22)
        if b % 2 == 1:
            place(buf, tone(hz(chord[0] + 24 + MRNG.integers(0, 3) * 2), 0.25, "sine", 0.002, 14), t0 + 3.5 * beat, 0.12)
    write_music("menu", buf, 0.6)

    # Run: 120 BPM, 8 bars, two layers of the same length.
    beat = 60 / 120
    n_samples = int(RATE * beat * 4 * bars)
    base = np.zeros(n_samples)
    drive = np.zeros(n_samples)
    hat = np.diff(MRNG.uniform(-1, 1, int(RATE * 0.05) + 1)) * np.exp(-60 * _t(0.05))
    snare = MRNG.uniform(-1, 1, int(RATE * 0.16)) * np.exp(-22 * _t(0.16))
    kick = np.sin(2 * np.pi * np.cumsum(np.geomspace(140, 45, int(RATE * 0.3))) / RATE) * np.exp(-9 * _t(0.3))
    for b in range(bars):
        chord = PROG[(b // 2) % 4]
        t0 = b * 4 * beat
        if b % 2 == 0:
            place(base, pad([hz(n - 12) for n in chord], beat * 8 + 0.4), t0, 0.35)
        for e in range(8):  # bass on eighths
            n = chord[0] - 24 + (7 if e in (3, 7) else 0)
            place(base, tone(hz(n), beat * 0.48, "soft", 0.004, 7), t0 + e * beat / 2, 0.5)
        for e in range(8):  # mid arpeggio on eighths
            place(base, tone(hz(chord[e % 3] + 12), 0.3, "tri", 0.003, 9), t0 + e * beat / 2, 0.12)
        for q in range(4):
            place(drive, kick, t0 + q * beat, 0.9)
            place(drive, hat, t0 + q * beat + beat / 2, 0.25)
            if q in (1, 3):
                place(drive, snare, t0 + q * beat, 0.35)
        for s16 in range(16):  # bright sixteenth arpeggio
            n = chord[(s16 * 2) % 3] + 24
            place(drive, tone(hz(n), 0.15, "tri", 0.002, 18), t0 + s16 * beat / 4, 0.09)
    write_music("run_base", base, 0.6)
    write_music("run_drive", drive, 0.6)


def build_background(size: int = 512, bg="#1d1433", dots="#2a1e48", cells="#251a40") -> None:
    """Seamless 512px tile of faint dots and cells (drawn tiled under the world)."""
    rng = np.random.default_rng(99)
    scale = 4  # supersample for smooth edges
    img = Image.new("RGB", (size * scale, size * scale), bg)
    d = ImageDraw.Draw(img)

    def blob(x, y, r, col):
        for ox in (-size, 0, size):  # wrap so the tile is seamless
            for oy in (-size, 0, size):
                cx, cy = (x + ox) * scale, (y + oy) * scale
                d.ellipse([cx - r * scale, cy - r * scale, cx + r * scale, cy + r * scale], fill=col)

    for _ in range(6):
        blob(rng.uniform(0, size), rng.uniform(0, size), rng.uniform(18, 44), cells)
    for _ in range(26):
        blob(rng.uniform(0, size), rng.uniform(0, size), rng.uniform(2.0, 4.5), dots)
    img = img.resize((size, size), Image.LANCZOS)
    out = ROOT / "assets" / "processed" / "bg_tile.png"
    img.save(out, optimize=True)
    print(f"wrote {out.name}")


if __name__ == "__main__":
    build_sfx()
    build_background()
    build_music()
