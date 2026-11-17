#!/usr/bin/env bash
# Android versionCode for every APK/AAB build: 2 x seconds since 2026-01-01 UTC,
# +1 for the store AAB. One rising number shared by android.yml and store.yml,
# so a later build always has a higher code whichever workflow made it (Play
# rejects a lower or equal code). A v* tag starts both workflows at once: the
# parity keeps the test APK and the AAB from ever sharing a code, and seconds
# keep two runs of one workflow apart. Stays below Play's 2,100,000,000 limit
# until ~2059. Earlier builds used minutes (< 1,000,000), so these install as
# updates.
# Usage: tools/version_code.sh [apk|store]   (default apk) -> prints the code
set -euo pipefail
kind="${1:-apk}"
case "$kind" in
  apk) odd=0 ;;
  store) odd=1 ;;
  *) echo "usage: $0 [apk|store]" >&2; exit 2 ;;
esac
echo $(( ( $(date -u +%s) - 1767225600 ) * 2 + odd ))
