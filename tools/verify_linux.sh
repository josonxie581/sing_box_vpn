#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
bundle=$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")}")
for tool in ldd nm readelf; do
  command -v "$tool" >/dev/null || { echo "Missing verification tool: $tool" >&2; exit 1; }
done
for file in gsou lib/libsingbox.so lib/libflutter_linux_gtk.so lib/libapp.so \
  data/icudtl.dat data/flutter_assets/AssetManifest.bin \
  data/flutter_assets/assets/app_icon.png data/com.gsou.gsou.desktop data/gsou.service; do
  [[ -s "$bundle/$file" ]] || { echo "Missing or empty: $bundle/$file" >&2; exit 1; }
done
for binary in "$bundle/gsou" "$bundle"/lib/*.so; do
  # We inspect ELF metadata, not the engine's linked DWARF debug information.
  readelf -wN -h "$binary" >/dev/null
  dynamic=$(readelf -wN -d "$binary")
  # Dart's libapp.so is an AOT snapshot and can have no shared dependencies.
  if [[ $dynamic != *'(NEEDED)'* ]]; then continue; fi
  # Resolve a standalone plugin the same way as when the runner has already
  # loaded Flutter from the bundle. This variable is only for the inspection.
  dependencies=$(LD_LIBRARY_PATH="$bundle/lib" ldd "$binary" 2>&1) || {
    echo "$dependencies" >&2; exit 1;
  }
  if [[ $dependencies == *'not found'* ]]; then
    echo "$binary: $dependencies" >&2; exit 1
  fi
done
exports=$(nm -D --defined-only "$bundle/lib/libsingbox.so")
for symbol in InitSingBox StartSingBox StopSingBox IsRunning TestConfig Cleanup GetVersion ProbeNodeDelay; do
  grep -Eq "[[:space:]]${symbol}$" <<< "$exports" || {
    echo "Missing native export: $symbol" >&2; exit 1;
  }
done
echo 'Linux bundle files, dynamic dependencies and native exports verified.'
