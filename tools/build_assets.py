#!/usr/bin/env python3
"""Rebuild everything in assets/processed/ from code and assets/raw/.

Synthesises most sound effects (sfxr-style: oscillators, pitch sweeps, noise
and envelopes), builds the kill/impact sounds from CC0 recordings in
assets/raw/sfx_cc0/ (trimmed, pitched and layered with a synth body), and
draws the tiled background. Output is deterministic.

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
RAW_SFX = ROOT / "assets" / "raw" / "sfx_cc0"
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


def sample(rel: str, dur: float, pitch: float = 1.0, fade: float = 0.06, lead: float = 0.003) -> np.ndarray:
    """A CC0 recording from assets/raw/sfx_cc0: mono, resampled to RATE
    (pitch > 1 = higher and shorter), cut from just before its onset to
    `dur` seconds with a short fade-out, peak-normalised to 1."""
    with wave.open(str(RAW_SFX / rel), "rb") as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32768.0
    n_out = int(x.size * RATE / sr / pitch)
    x = np.interp(np.linspace(0, x.size - 1, n_out), np.arange(x.size), x)
    x = x / max(np.abs(x).max(), 1e-6)
    on = max(0, int(np.argmax(np.abs(x) > 0.1)) - int(lead * RATE))
    x = x[on: on + int(dur * RATE)].copy()
    f = min(int(fade * RATE), x.size)
    x[x.size - f:] *= np.linspace(1, 0, f) ** 2
    a = min(int(0.002 * RATE), x.size)
    x[:a] *= np.linspace(0, 1, a)
    return x / max(np.abs(x).max(), 1e-6)


def body(f0: float, f1: float, dur: float, amp: float) -> np.ndarray:
    """A low sine 'thump' layered under a recording for weight."""
    return env(osc(f0, f1, dur, "sine"), attack=0.002, decay_pow=2.2) * amp


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
    # Old synth hit/kill/bomb/kill2: replaced by recordings below, but still
    # computed so the shared noise RNG (and every sound after them) is unchanged.
    env(mix(osc(300, 120, 0.06, "square"), noise(0.06) * 0.4))
    env(mix(osc(520, 90, 0.16, "tri"), noise(0.16, 0.3) * 0.6), decay_pow=2.5)
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
    env(mix(osc(120, 30, 0.9, "sine"), noise(0.9, 0.04) * 1.2), attack=0.005, decay_pow=1.6)
    write("chest", seq(*[env(osc(f, f, 0.07, "tri"), decay_pow=0.9) for f in (392, 494, 587, 784, 988)]), 0.6)
    write("claim", seq(env(osc(330, 660, 0.12, "tri"), decay_pow=0.8), env(osc(660, 990, 0.16, "sine"), decay_pow=1.2)), 0.6)
    write("convert", env(mix(osc(300, 900, 0.22, "tri"), osc(450, 1350, 0.22, "sine") * 0.5), attack=0.01, decay_pow=1.1), 0.5)
    # Meta shop: a bright rising chime with a sparkle tail; a soft low "nope".
    write("upgrade", mix(seq(*[env(osc(f, f, 0.07, "tri"), decay_pow=0.9) for f in (523, 784, 1047)], env(osc(1568, 2093, 0.28, "sine"), decay_pow=1.4)), np.pad(env(noise(0.2, 0.6), decay_pow=2.5) * 0.25, (int(0.21 * RATE), 0))), 0.6)
    write("deny", seq(env(osc(196, 180, 0.07, "square"), decay_pow=0.7), env(osc(147, 130, 0.12, "square"), decay_pow=1.0)), 0.35)
    write("evolve", mix(*[env(osc(f, f * 2, 0.9, "saw"), attack=0.02, decay_pow=1.2) * 0.4 for f in (262, 330, 392, 523)]), 0.8)
    # Added later: keep new sounds at the end so the shared noise RNG doesn't
    # change the sounds above.
    env(mix(osc(640, 150, 0.14, "tri"), noise(0.14, 0.4) * 0.5), decay_pow=2.2)
    # Low-HP heartbeat: "lub-dub", two soft low thumps (sine only).
    write("heartbeat", seq(env(osc(95, 48, 0.13, "sine"), attack=0.004, decay_pow=2.4), np.zeros(int(0.08 * RATE)), env(osc(85, 42, 0.11, "sine"), attack=0.004, decay_pow=2.6) * 0.7, np.zeros(int(0.05 * RATE))), 0.9)
    build_cc0_sfx()
    build_pop_sfx()


def build_cc0_sfx() -> None:
    """Kill feel (2026-11-06): CC0 recordings (assets/raw/sfx_cc0/SOURCES.md)
    with a synth low end so small phone speakers still get some weight."""
    squish = ["ezduzziteh_squish/squish_01.wav", "ezduzziteh_squish/squish_02.wav", "ezduzziteh_squish/squish_03.wav",
              "ezduzziteh_squish/squish_04.wav", "independent_nu/impactsplat03.wav", "independent_nu/impactsplat01.wav"]
    for k, rel in enumerate(squish):  # germ pops: kill1..kill6, matched in loudness (RMS)
        x = mix(sample(rel, 0.24, pitch=1.05), body(190, 70, 0.09, 0.55))
        x = x / max(np.abs(x).max(), 1e-6)
        write(f"kill{k + 1}", x, min(0.85, 0.12 / float(np.sqrt((x ** 2).mean()))))
    # Many kills in one frame: a deep punch with a sub drop.
    write("thump", mix(sample("qubodup_punch/punch03.wav", 0.32, pitch=0.62), body(95, 36, 0.32, 0.9)), 0.85)
    # Elite kill: a crunch plus a wet splat and a low hit.
    write("crunch", mix(sample("independent_nu/impactcrunch04.wav", 0.36), sample("ezduzziteh_squish/squish_02.wav", 0.24, pitch=0.8) * 0.6,
                        body(120, 45, 0.26, 0.7)), 0.85)
    # Critical hit: a sharp punch with a bright tick on top.
    write("crit", mix(sample("qubodup_punch/punch01.wav", 0.2, pitch=1.15), env(osc(2600, 1900, 0.035, "tri"), decay_pow=1.5) * 0.25), 0.7)
    # Weapon hit: a short dry tap (very frequent, so tiny and quiet).
    write("hit", sample("starninjas_impact/impact_8.wav", 0.09, pitch=1.25, fade=0.04), 0.5)
    # Mega kill and bomb: the explosion with an added sub boom.
    write("mega", mix(sample("joth_chunky_explosion/chunky_explosion.wav", 1.6, fade=0.6), body(70, 28, 0.9, 0.8)), 0.9)
    write("bomb", mix(sample("joth_chunky_explosion/chunky_explosion.wav", 1.0, pitch=1.15, fade=0.45), body(90, 32, 0.6, 0.7)), 0.9)


def build_pop_sfx() -> None:
    """Cosmetic pop styles (2026-11-06, data/cosmetics.json "sound"): short
    synth kill sounds, loudness matched to the squelches (RMS). Built after
    everything else so the shared noise RNG leaves older sounds unchanged."""
    def rms_write(name: str, x: np.ndarray) -> None:
        x = x / max(np.abs(x).max(), 1e-6)
        write(name, x, min(0.85, 0.12 / float(np.sqrt((x ** 2).mean()))))
    # Bubbles: a round "bloop" that rises, then a tiny second pop.
    rms_write("pop_bubble", seq(env(osc(320, 1100, 0.06, "sine"), attack=0.002, decay_pow=1.4),
                                env(osc(900, 1500, 0.035, "sine"), attack=0.001, decay_pow=2.0) * 0.5))
    # Pixels: an 8-bit square blip falling an octave.
    rms_write("pop_blip", seq(env(osc(1320, 1320, 0.03, "square"), decay_pow=0.5), env(osc(660, 440, 0.06, "square"), decay_pow=1.5)))
    # Jackpot: the classic two-note coin.
    rms_write("pop_coin", seq(env(osc(988, 988, 0.05, "square"), decay_pow=0.4), env(osc(1319, 1319, 0.16, "square"), decay_pow=1.3)))
    # Fireworks / Supernova: a bright crackle over a falling chirp.
    rms_write("pop_spark", mix(env(noise(0.16, 0.9), attack=0.001, decay_pow=2.5) * 0.7,
                               env(osc(2400, 700, 0.14, "tri"), attack=0.002, decay_pow=1.6) * 0.6, body(160, 60, 0.08, 0.5)))
    # Confetti: a party-popper snap with a short rising whistle.
    rms_write("pop_party", mix(env(noise(0.05, 0.6), attack=0.001, decay_pow=3.0),
                               np.pad(env(osc(900, 2200, 0.1, "sine"), attack=0.005, decay_pow=1.2) * 0.5, (int(0.02 * RATE), 0))))
    # --- Second batch (2026-11-06, appended so everything above is unchanged).
    # Shatter: a glassy crack (bright noise) with three high pings ringing out.
    rms_write("pop_glass", mix(env(noise(0.05, 0.95), attack=0.0005, decay_pow=3.0) * 0.8,
                               *[env(osc(f, f * 0.98, 0.22, "sine"), attack=0.001, decay_pow=3.0) * a for f, a in ((3150, 0.5), (4420, 0.35), (5230, 0.25))]))
    # Melody: one soft bell note (sine + inharmonic partials); the game plays
    # it at the notes of a scale, so kills turn into a tune.
    rms_write("pop_chime", mix(*[env(osc(880 * r, 880 * r, 0.32, "sine"), attack=0.002, decay_pow=a) * g
                                 for r, a, g in ((1.0, 2.2, 1.0), (2.0, 3.0, 0.35), (2.76, 4.0, 0.2), (5.4, 6.0, 0.08))]))
    # Zap: an electric crackle diving down.
    rms_write("pop_zap", mix(env(osc(3200, 180, 0.11, "saw"), attack=0.001, decay_pow=1.4) * 0.6,
                             env(noise(0.09, 0.85), attack=0.001, decay_pow=2.0) * 0.5))
    # Slime: a slow, low, sloppy squelch.
    rms_write("pop_slime", mix(sample("ezduzziteh_squish/squish_03.wav", 0.3, pitch=0.62), body(120, 45, 0.22, 0.7)))
    # Kaboom: a tiny explosion with a sub kick.
    rms_write("pop_boom", mix(sample("joth_chunky_explosion/chunky_explosion.wav", 0.32, pitch=1.7, fade=0.14), body(110, 38, 0.2, 0.9)))
    # Squeaky: a rubber-toy squeak (rise, wobble, fall).
    sq = osc(1100, 1700, 0.07, "sine")
    rms_write("pop_squeak", env(mix(seq(sq, osc(1700, 1150, 0.08, "sine")), seq(osc(1100, 1700, 0.07, "tri"), osc(1700, 1150, 0.08, "tri")) * 0.3), attack=0.004, decay_pow=0.8))


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


# --------------------------------------------------------------------------
# Overhaul art (docs/CRAZYGAMES_PLAN.md Phase R1, "dark-field microscope"):
# glowing, rim-lit translucent cells on a near-black slide. Written next to
# the old art into assets/processed/overhaul/ and picked at runtime only when
# the overhaul is on (balance.overhaul), so the old look stays available.
# All white/grey: the game tints each sprite (SpriteBatch colours).

DF_BODY = 0.6        # germ body radius as a fraction of the frame half-width
DF_DIRS = 16         # facing directions per row (frame k faces angle k*TAU/16)
DF_FRAME = 64        # px per frame
DF_CELL_BODY = 0.78  # player body fraction (same as ShapeTextures.CELL_BODY)


def _smin(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """Smooth union of two signed distances (k = blend width)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def _circ(x, y, cx, cy, r):
    return np.hypot(x - cx, y - cy) - r


def _germ_sdf(kind: str, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Signed distance (frame units, < 0 inside) of one germ type, facing +x."""
    B = DF_BODY
    th = np.arctan2(y, x)
    rr = np.hypot(x, y)
    if kind == "grunt":      # coccus with soft knobs
        return rr - B * (1 + 0.06 * np.cos(7 * th))
    if kind == "swarm":      # tiny spiky spore
        return rr - B * 0.78 * (1 + 0.26 * np.maximum(np.cos(9 * th), 0) ** 3)
    if kind == "runner":     # comet: round head, tapering tail
        return _smin(_circ(x, y, 0.1 * B, 0, 0.78 * B), _circ(x, y, -0.62 * B, 0, 0.32 * B), 0.3 * B)
    if kind == "brute":      # big irregular lump
        return rr - B * (1 + 0.08 * np.cos(3 * th + 1.0) + 0.05 * np.cos(5 * th + 2.0))
    if kind == "spitter":    # round body with a nozzle toward you
        seg = np.clip(x, 0.5 * B, 1.1 * B)
        nozzle = np.hypot(x - seg, y) - 0.2 * B
        return _smin(_circ(x, y, -0.05 * B, 0, 0.88 * B), nozzle, 0.12 * B)
    if kind == "charger":    # spindle pointing at you
        a, b = 1.22 * B, 0.56 * B
        return (np.hypot(x / a, y / b) - 1.0) * b
    if kind == "splitter":   # dividing cell: two lobes and a waist
        return _smin(_circ(x, y, 0, -0.42 * B, 0.66 * B), _circ(x, y, 0, 0.42 * B, 0.66 * B), 0.08 * B)
    if kind == "boss":       # wavy mother cell
        return rr - B * (1 + 0.045 * np.cos(11 * th) + 0.03 * np.cos(4 * th))
    raise SystemExit(f"build_overhaul_art: no dark-field shape for enemy '{kind}' (add one)")


# Per-type insides: (organelles [(x, y, r) in units of B], nucleus (x, y, r) or None, rotates with facing)
_GERM_INSIDE = {
    "grunt": ([(-0.35, 0.4, 0.09), (-0.5, -0.2, 0.07), (0.05, 0.55, 0.06)], (-0.15, 0.05, 0.3), False),
    "swarm": ([], None, False),
    "runner": ([(-0.45, 0.12, 0.08)], (-0.05, 0.0, 0.26), True),
    "brute": ([(-0.5, 0.35, 0.1), (-0.3, -0.5, 0.08), (0.2, 0.55, 0.09), (-0.65, -0.05, 0.07), (0.3, -0.55, 0.06)], (-0.1, 0.0, 0.36), False),
    "spitter": ([(-0.45, 0.35, 0.08), (-0.4, -0.4, 0.07)], (-0.2, 0.0, 0.28), True),
    "charger": ([(-0.75, 0.0, 0.1), (-0.45, 0.2, 0.06)], (-0.1, 0.0, 0.24), True),
    "splitter": ([(0.25, -0.5, 0.07), (-0.25, 0.5, 0.07)], None, False),
    "boss": ([(-0.5, 0.45, 0.1), (0.3, 0.6, 0.08), (-0.6, -0.3, 0.09), (0.45, -0.55, 0.07), (-0.2, -0.65, 0.06), (0.65, 0.1, 0.06)], (-0.15, 0.05, 0.4), False),
}


def _germ_frame(kind: str, ang: float, n: int) -> np.ndarray:
    """One RGBA frame (float 0..1), the germ facing angle `ang`."""
    B = DF_BODY
    c = (np.arange(n) + 0.5) / n * 2 - 1
    px, py = np.meshgrid(c, c)
    rotates = kind in ("runner", "spitter", "charger")
    ca, sa = np.cos(-ang), np.sin(-ang)
    lx, ly = px * ca - py * sa, px * sa + py * ca  # local: +x faces the target
    sx, sy = (lx, ly) if rotates else (px, py)
    d = _germ_sdf(kind, sx, sy)
    aa = 2.0 / n  # one pixel in frame units
    inside = np.clip(0.5 - d / aa, 0, 1)
    # Rim-lit membrane (bright, thin), a translucent body brighter toward the
    # rim (dark-field look), and a soft outer glow.
    rim = np.exp(-((d + 0.025) / 0.035) ** 2)
    body_v = 0.42 + 0.4 * np.clip(1 + d / (0.35 * B), 0, 1) ** 2
    glow = 0.5 * np.exp(-np.maximum(d, 0) / 0.075) * (d > 0)
    v = np.where(inside > 0, body_v, 1.0)
    a = np.maximum(inside * 0.58, glow)
    orgs, nuc, nuc_rot = _GERM_INSIDE[kind]
    ox, oy = (lx, ly) if nuc_rot else (px, py)
    for (gx, gy, gr) in orgs:  # bright granules
        g = np.clip(0.5 - _circ(ox, oy, gx * B, gy * B, gr * B) / aa, 0, 1) * inside
        v = v * (1 - g) + 0.95 * g
        a = np.maximum(a, g * 0.8)
    nuclei = [nuc] if nuc else []
    if kind == "splitter":
        nuclei = [(0.0, -0.42, 0.24), (0.0, 0.42, 0.24)]
    for (nx, ny, nr) in nuclei:  # nucleus: a dim core with its own faint rim
        nd = _circ(ox, oy, nx * B, ny * B, nr * B)
        core = np.clip(0.5 - nd / aa, 0, 1) * inside
        v = v * (1 - core) + 0.55 * core
        a = np.maximum(a, core * 0.62)
        nrim = np.exp(-(nd / 0.02) ** 2) * inside
        v = np.maximum(v, 0.9 * nrim)
        a = np.maximum(a, nrim * 0.7)
    a = np.maximum(a, rim * np.clip(1.2 - np.abs(d) / 0.08, 0, 1))
    v = np.maximum(v, rim)
    # Eyes (always face the target): dark pupils with a tiny highlight.
    er = (0.13 if kind == "swarm" else 0.17) * B
    ex = (0.3 if kind == "swarm" else 0.36) * B
    if kind == "charger":
        ex = 0.62 * B
    if kind == "boss":
        er, ex = 0.12 * B, 0.45 * B
    for side in (-1, 1):
        ey = side * (0.24 if kind == "swarm" else 0.3) * B
        ed = _circ(lx, ly, ex, ey, er)
        eye = np.clip(0.5 - ed / aa, 0, 1)
        v = v * (1 - eye) + 0.06 * eye
        a = np.maximum(a, eye)
        hl = np.clip(0.5 - _circ(lx, ly, ex + 0.35 * er, ey - 0.35 * er, 0.32 * er) / aa, 0, 1)
        v = v * (1 - hl) + 1.0 * hl
    a = a * np.clip((1.0 - np.hypot(px, py)) / 0.1, 0, 1)  # glow never reaches the frame edge
    return np.dstack([v, v, v, np.clip(a, 0, 1)])


def _save_rgba(arr: np.ndarray, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(out, optimize=True)
    print(f"wrote {out.relative_to(ROOT)}")


def build_overhaul_germs() -> None:
    """germs_df.png: one row per enemy (data/enemies.json order), DF_DIRS facings."""
    import json
    ids = [e["id"] for e in json.loads((ROOT / "data" / "enemies.json").read_text())]
    n = DF_FRAME
    atlas = np.zeros((n * len(ids), n * DF_DIRS, 4))
    for row, kind in enumerate(ids):
        for k in range(DF_DIRS):
            atlas[row * n:(row + 1) * n, k * n:(k + 1) * n] = _germ_frame(kind, 2 * np.pi * k / DF_DIRS, n)
    _save_rgba(atlas, ROOT / "assets" / "processed" / "overhaul" / "germs_df.png")


def build_overhaul_player(n: int = 128) -> None:
    """player_df.png: the rim-lit white cell (nucleus drawn by the game)."""
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, c)
    body = DF_CELL_BODY
    d = np.hypot(x, y) - body * (1 + 0.015 * np.cos(9 * np.arctan2(y, x)))
    aa = 2.0 / n
    inside = np.clip(0.5 - d / aa, 0, 1)
    rim = np.exp(-((d + 0.02) / 0.03) ** 2)
    v = np.where(inside > 0, 0.55 + 0.4 * np.clip(1 + d / 0.3, 0, 1) ** 2, 1.0)
    a = np.maximum(inside * 0.62, 0.55 * np.exp(-np.maximum(d, 0) / 0.07) * (d > 0))
    for (gx, gy, gr) in [(0.32, 0.36, 0.06), (-0.38, 0.22, 0.05), (0.12, -0.45, 0.045), (-0.2, 0.5, 0.04), (0.45, -0.1, 0.035)]:
        g = np.clip(0.5 - _circ(x, y, gx, gy, gr) / aa, 0, 1) * inside
        v = v * (1 - g) + 1.0 * g
        a = np.maximum(a, g * 0.9)
    v = np.maximum(v, rim)
    a = np.maximum(a, rim)
    _save_rgba(np.dstack([v, v, v, a]), ROOT / "assets" / "processed" / "overhaul" / "player_df.png")


def build_overhaul_background(size: int = 512) -> None:
    """bg_df.png: a dark-field slide: near-black, out-of-focus debris, faint
    specks and a counting-chamber grid (lines every 128 px, triple lines at
    the tile edge). Seamless (everything wraps)."""
    rng = np.random.default_rng(11)
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    base = np.array([5, 8, 18], float)
    img = np.zeros((size, size, 3)) + base

    def wrap_d(cx, cy):
        dx = np.abs(xx - cx); dx = np.minimum(dx, size - dx)
        dy = np.abs(yy - cy); dy = np.minimum(dy, size - dy)
        return np.hypot(dx, dy)

    for _ in range(9):  # out-of-focus cells: soft rings, barely there
        cx, cy, r = rng.uniform(0, size), rng.uniform(0, size), rng.uniform(26, 60)
        dd = wrap_d(cx, cy)
        ring = np.exp(-((dd - r) / 7.0) ** 2) * 0.9 + np.exp(-(dd / r) ** 2) * 0.35
        img += ring[..., None] * np.array([3, 6, 12]) * rng.uniform(0.5, 1.0)
    for _ in range(70):  # specks of debris
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        dd = wrap_d(cx, cy)
        img += (np.exp(-(dd / rng.uniform(0.8, 1.8)) ** 2) * rng.uniform(25, 60))[..., None] * np.array([0.6, 0.85, 1.0])
    # Counting-chamber grid.
    def line_mask(coord, period, offs, width):
        m = np.zeros_like(coord)
        for o in offs:
            dd = np.abs(((coord - o + period / 2) % period) - period / 2)
            m = np.maximum(m, np.exp(-(dd / width) ** 2))
        return m
    fine = np.maximum(line_mask(xx, 128, [0], 0.7), line_mask(yy, 128, [0], 0.7))
    edge = np.maximum(line_mask(xx, 512, [0, 6, 12], 0.8), line_mask(yy, 512, [0, 6, 12], 0.8))
    img += fine[..., None] * np.array([8, 16, 30]) + edge[..., None] * np.array([10, 20, 38])
    img += rng.normal(0, 1.2, (size, size, 1))
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(ROOT / "assets" / "processed" / "overhaul" / "bg_df.png", optimize=True)
    print("wrote assets/processed/overhaul/bg_df.png")


def build_overhaul_art() -> None:
    build_overhaul_germs()
    build_overhaul_player()
    build_overhaul_background()


def build_evolution_sfx() -> None:
    """Phase S3-S5 (overhaul): each evolved weapon gets its own sound, so an
    evolution is heard as well as seen. Own RNG, so the other sounds never
    change when these are rebuilt (python3 tools/build_assets.py --evo-sfx)."""
    rng = np.random.default_rng(4747)

    def hiss(dur: float, bright: float = 0.6) -> np.ndarray:
        """Sizzle: white noise with random crackle spikes, high-passed."""
        n = rng.uniform(-1, 1, int(RATE * dur))
        crackle = (rng.uniform(0, 1, n.size) > 0.985) * rng.uniform(-1, 1, n.size) * 3.0
        x = n * bright + crackle
        return np.diff(x, prepend=0.0)  # first difference = a cheap high-pass

    # Fever Spike, pulse 1: a deep heat whump (the explosion recording an
    # octave down + a sub drop) that dies into a crackling sizzle.
    boom = sample("joth_chunky_explosion/chunky_explosion.wav", 0.55, pitch=0.62, fade=0.3)
    fever = mix(boom * 0.8, body(110, 34, 0.5, 1.0), np.concatenate([np.zeros(int(0.04 * RATE)), env(hiss(0.7), attack=0.05, decay_pow=1.6) * 0.35]))
    write("fever", fever, 0.9)
    # Pulse 2: higher and sharper, a white-hot crack with a brighter sizzle.
    crack = sample("joth_chunky_explosion/chunky_explosion.wav", 0.35, pitch=1.05, fade=0.2)
    fever2 = mix(crack * 0.75, body(220, 70, 0.3, 0.8), env(osc(1800, 600, 0.12, "tri"), decay_pow=1.4) * 0.25,
                 env(hiss(0.55, 0.9), attack=0.01, decay_pow=1.8) * 0.4)
    write("fever2", fever2, 0.85)


if __name__ == "__main__":
    import sys
    if "--evo-sfx" in sys.argv:  # only the evolved-weapon sounds (fast)
        build_evolution_sfx()
        raise SystemExit(0)
    if "--overhaul" in sys.argv:  # only the overhaul art (fast)
        build_overhaul_art()
        raise SystemExit(0)
    build_sfx()
    build_background()
    build_overhaul_art()
    build_evolution_sfx()
