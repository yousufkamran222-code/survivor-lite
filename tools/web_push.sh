#!/usr/bin/env bash
# Export the web build and upload it to itch.io (light213/petri, channel html5).
# Usage (repo root): tools/web_push.sh [path/to/butler]
# Needs: Godot export templates (web) installed, butler, and BUTLER_API_KEY in
# the environment (never commit it). The menu shows the build SHA.
set -euo pipefail
BUTLER="${1:-butler}"
TARGET="light213/petri:html5"
SHA="$(git rev-parse --short=7 HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then SHA="${SHA}+"; fi  # uncommitted changes
echo "{\"sha\": \"${SHA}\", \"run\": 0, \"built\": \"$(date -u +%Y-%m-%dT%H:%MZ)\"}" > data/build_info.json
rm -rf build/web && mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
ls -la build/web
"$BUTLER" push build/web "$TARGET" --userversion "$SHA"
"$BUTLER" status "$TARGET"
