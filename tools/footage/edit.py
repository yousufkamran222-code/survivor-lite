#!/usr/bin/env python3
"""Footage editing with ffmpeg: frames -> clips, clips -> a trailer.

  python3 tools/footage/edit.py encode FRAMES_DIR OUT.mp4
      PNG frames (00000.png ...) at 60 fps -> a high-quality H.264 clip.

  python3 tools/footage/edit.py trailer SPEC.json OUT.mp4
      SPEC: {"size": [1920, 1080], "cover": "cover.png", "cover_s": 1.0,
             "fade": 0.12, "crf": 17, "segments": [["clip.mp4", start_s, dur_s], ...]}
      Opens on the static cover (CrazyGames: the video starts on the cover),
      then the segments with short crossfades. Silent, 60 fps, yuv420p,
      faststart. Prints the length and size.
"""
import json
import subprocess
import sys

FPS = 60


def run(cmd):
    print(" ".join(cmd[:6]), "...")
    subprocess.run(cmd, check=True)


def encode(frames, out):
    run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", f"{frames}/%05d.png",
         "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out])


def probe_len(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                       capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def trailer(spec_path, out):
    spec = json.load(open(spec_path))
    w, h = spec["size"]
    fade = float(spec.get("fade", 0.12))
    inputs = []
    filters = []
    labels = []
    lens = []
    scale = f"scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,crop={w}:{h},fps={FPS},format=yuv420p,setsar=1"
    if spec.get("cover"):
        cs = float(spec.get("cover_s", 1.0))
        inputs += ["-loop", "1", "-t", str(cs + fade), "-i", spec["cover"]]
        filters.append(f"[0:v]{scale},trim=0:{cs + fade},setpts=PTS-STARTPTS[s0]")
        labels.append("s0")
        lens.append(cs + fade)
    for seg in spec["segments"]:
        clip, start, dur = seg[0], float(seg[1]), float(seg[2])
        k = len(labels)
        inputs += ["-i", clip]
        extra = seg[3] if len(seg) > 3 else ""
        filters.append(f"[{k}:v]trim={start}:{start + dur + fade},setpts=PTS-STARTPTS,{scale}{(',' + extra) if extra else ''}[s{k}]")
        labels.append(f"s{k}")
        lens.append(dur + fade)
    # Crossfade chain.
    cur = labels[0]
    t = lens[0] - fade
    for i in range(1, len(labels)):
        nxt = f"x{i}"
        filters.append(f"[{cur}][{labels[i]}]xfade=transition=fade:duration={fade}:offset={t:.3f}[{nxt}]")
        cur = nxt
        t += lens[i] - fade
    total = t + fade
    run(["ffmpeg", "-y", "-loglevel", "error"] + inputs + ["-filter_complex", ";".join(filters), "-map", f"[{cur}]",
         "-t", f"{total:.3f}", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", str(spec.get("crf", 17)), "-pix_fmt", "yuv420p",
         "-r", str(FPS), "-movflags", "+faststart", out])
    import os
    print(f"{out}: {probe_len(out):.2f} s, {os.path.getsize(out) / 1e6:.1f} MB")


if __name__ == "__main__":
    if sys.argv[1] == "encode":
        encode(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "trailer":
        trailer(sys.argv[2], sys.argv[3])
