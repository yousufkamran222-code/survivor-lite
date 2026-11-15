#!/usr/bin/env bash
# Export the CrazyGames web build (preset "CrazyGames", feature "crazygames":
# no ads, no dev tools, SKIP TUTORIAL in Patient Zero) and zip it for upload
# in the CrazyGames developer portal. docs/CRAZYGAMES_PLAN.md.
# Usage (repo root): tools/crazygames_build.sh  -> build/crazygames.zip
# Needs the Godot web export templates. Test locally from http://127.0.0.1
# (CrazyGames' sitelock allows localhost), never from itch.io.
set -euo pipefail
SHA="$(git rev-parse --short=7 HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then SHA="${SHA}+"; fi  # uncommitted changes
echo "{\"sha\": \"${SHA}\", \"run\": 0, \"built\": \"$(date -u +%Y-%m-%dT%H:%MZ)\"}" > data/build_info.json
rm -rf build/crazygames build/crazygames.zip && mkdir -p build/crazygames
godot --headless --path . --export-release "CrazyGames" build/crazygames/index.html
rm -f build/crazygames/*.import
(cd build/crazygames && zip -q -r ../crazygames.zip .)
ls -la build/crazygames build/crazygames.zip
