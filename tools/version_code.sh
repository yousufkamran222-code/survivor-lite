#!/usr/bin/env bash
# Android versionCode for every APK/AAB build: minutes since 2026-01-01 UTC.
# One rising number shared by android.yml and store.yml, so a later build
# always has a higher code whichever workflow made it (Play rejects a lower
# or equal code), and it stays far below Play's 2,100,000,000 limit (~4,000
# years). Old APKs used the run number (< 100), so these install as updates.
# Usage: tools/version_code.sh  -> prints the code
set -euo pipefail
echo $(( ( $(date -u +%s) - 1767225600 ) / 60 ))
