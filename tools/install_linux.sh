#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Linux ]] || { echo 'This installer requires Linux.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run: sudo bash install_linux.sh [bundle-directory]' >&2; exit 1; }
bundle=$(realpath -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")}")
target=/opt/gsou
for tool in setcap getcap patchelf pgrep; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool. See BUILD_LINUX.md." >&2; exit 1; }
done
[[ $bundle != "$target" && $bundle != "$target/"* ]] || {
  echo 'Install from a separate build/release bundle.' >&2; exit 1;
}
[[ ! -L $target ]] || { echo 'Refusing a symlink at /opt/gsou.' >&2; exit 1; }
if pgrep -x gsou >/dev/null; then
  echo 'Exit Gsou before installing or updating.' >&2; exit 1
fi
bash "$bundle/verify_linux.sh" "$bundle"
[[ -z $(find "$bundle" -type l -print -quit) ]] || {
  echo 'Bundle must contain real files, not external symlinks.' >&2; exit 1;
}
mkdir -p /opt
stage=$(mktemp -d /opt/gsou.install.XXXXXXXX)
trap 'if [[ -n ${stage:-} && $stage == /opt/gsou.install.* ]]; then rm -rf -- "$stage"; fi' EXIT
# Windows-backed 9p shares may reject ACL/xattr reads with EKEYREVOKED.
# Copy content only; Linux ownership, modes and capabilities are set below.
cp -R --no-preserve=all -- "$bundle/." "$stage/"
chown -R root:root "$stage"
chmod -R u+rwX,go+rX,go-w "$stage"
chmod 755 "$stage" "$stage/gsou"
# File capabilities trigger the loader's secure mode. Use a root-owned,
# absolute library directory rather than LD_LIBRARY_PATH or an unsafe origin.
patchelf --set-rpath /opt/gsou/lib "$stage/gsou"
if [[ -e $target ]]; then
  backup="/opt/gsou.backup.$(date +%Y%m%d-%H%M%S).$$"
  mv -- "$target" "$backup"
  echo "Previous installation retained: $backup"
fi
mv -- "$stage" "$target"
stage=
setcap cap_net_admin,cap_net_raw=ep "$target/gsou"
setcap -v cap_net_admin,cap_net_raw=ep "$target/gsou"
install -Dm644 "$target/data/com.gsou.gsou.desktop" /usr/share/applications/com.gsou.gsou.desktop
install -Dm644 "$target/data/gsou.service" /usr/lib/systemd/user/gsou.service
ln -sfn /opt/gsou/gsou /usr/local/bin/gsou
if command -v update-desktop-database >/dev/null; then update-desktop-database /usr/share/applications; fi
getcap "$target/gsou"
echo 'Installed. Start Gsou from the app launcher as your normal user.'
echo 'Auto-start can be enabled in Settings > DNS after opening Gsou.'
