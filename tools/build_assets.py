#!/usr/bin/env python3
"""Rebuild everything in assets/processed/ from code (and assets/raw/ later).

Right now this synthesises all sound effects (sfxr-style: oscillators, pitch
sweeps, noise and envelopes), so there are no licensing questions. Output is
deterministic: the same script always produces byte-identical files.

Usage:  python3 tools/build_assets.py
Needs:  numpy
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

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


if __name__ == "__main__":
    build_sfx()
