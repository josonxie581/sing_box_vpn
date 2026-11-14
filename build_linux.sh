#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$project_dir"
[[ $(uname -s) == Linux ]] || { echo 'Run this build in Omarchy / Linux.' >&2; exit 1; }
for tool in flutter go clang cmake ninja pkg-config git; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool. See BUILD_LINUX.md." >&2; exit 1; }
done
pkg-config --exists gtk+-3.0 || { echo 'Missing GTK3 development files.' >&2; exit 1; }
if ! pkg-config --exists ayatana-appindicator3-0.1 && ! pkg-config --exists appindicator3-0.1; then
  echo 'Missing AppIndicator development files. See BUILD_LINUX.md.' >&2; exit 1
fi
flutter pub get --enforce-lockfile
flutter build linux --release --no-pub "$@"
case $(uname -m) in
  x86_64) architecture=x64 ;;
  aarch64|arm64) architecture=arm64 ;;
  *) echo 'Unsupported Linux architecture.' >&2; exit 1 ;;
esac
bundle="$project_dir/build/linux/$architecture/release/bundle"
bash "$project_dir/tools/verify_linux.sh" "$bundle"
printf '\nBundle: %s\nInstall: sudo bash "%s/install_linux.sh"\n' "$bundle" "$bundle"
