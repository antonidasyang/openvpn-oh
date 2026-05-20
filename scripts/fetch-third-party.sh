#!/usr/bin/env bash
# Fetches the native dependencies under entry/src/main/cpp/third_party/.
# Pinned to commits known to compile cleanly with the HarmonyOS NDK as of 2026-Q1.
#
# Re-running is safe: each clone is skipped if the directory already exists.
set -euo pipefail

cd "$(dirname "$0")/.."
THIRD=entry/src/main/cpp/third_party
mkdir -p "$THIRD"
cd "$THIRD"

clone() {
  local url=$1 dir=$2 ref=$3
  if [[ -d "$dir/.git" ]]; then
    echo "[skip] $dir already exists"
    return
  fi
  echo "[clone] $url -> $dir @ $ref"
  git clone --depth 1 --branch "$ref" "$url" "$dir" || git clone "$url" "$dir"
  ( cd "$dir" && git checkout "$ref" )
}

clone https://github.com/OpenVPN/openvpn3.git openvpn3 release/3.10
clone https://github.com/chriskohlhoff/asio.git    asio    asio-1-30-2
clone https://github.com/Mbed-TLS/mbedtls.git      mbedtls v3.6.2
clone https://github.com/lz4/lz4.git               lz4     v1.10.0

cat <<EOM

Done. Next steps:
  1. Open the project in DevEco Studio 5.x.
  2. Make sure HarmonyOS NDK is installed (Preferences -> SDK -> Native).
  3. Build > Build Hap. If openvpn3 fails to compile against the OHOS NDK
     libc, see docs/PATCHES.md (you'll add patches for each non-portable
     POSIX call as they surface).
EOM
