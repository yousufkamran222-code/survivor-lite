#!/usr/bin/env bash
# Build the slim web export template (Phase S2, docs/CRAZYGAMES_PLAN.md):
# Godot (GODOT_VERSION) for the web without 3D, physics, navigation, XR,
# networking and unused formats (tools/web_engine/custom.py).
# Output: tools/web_engine/web_nothreads_release.zip, which the CrazyGames and
# Web export presets use as their custom release template.
# Needs: git, python3 + scons, ~6 GB disk; ~1 h on 4 cores.
# Usage (repo root): tools/web_engine/build.sh [work_dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VER="$(cat "$ROOT/GODOT_VERSION")"
EM_VERSION=4.0.11  # Godot 4.7's .github/workflows/web_builds.yml
WORK="${1:-/opt/gbuild}"
mkdir -p "$WORK"
cd "$WORK"
[ -d godot ] || git clone -q --depth 1 --branch "${VER}-stable" https://github.com/godotengine/godot godot
[ -d emsdk ] || git clone -q --depth 1 https://github.com/emscripten-core/emsdk emsdk
(cd emsdk && ./emsdk install "$EM_VERSION" && ./emsdk activate "$EM_VERSION") >/dev/null
# shellcheck disable=SC1091
source emsdk/emsdk_env.sh >/dev/null 2>&1
command -v scons >/dev/null || pip install scons
cd godot
scons -j"$(nproc)" profile="$ROOT/tools/web_engine/custom.py" target=template_release
cp bin/godot.web.template_release.wasm32.nothreads.zip "$ROOT/tools/web_engine/web_nothreads_release.zip"
ls -la "$ROOT/tools/web_engine/web_nothreads_release.zip"
