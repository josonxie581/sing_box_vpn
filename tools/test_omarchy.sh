#!/usr/bin/env bash
# Run from an Omarchy desktop terminal. Results stay beside this script.
set -euo pipefail
bundle=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
report="$bundle/omarchy-test.log"
exec > >(tee "$report") 2>&1
echo "Gsou Omarchy validation: $(date -Is)"
uname -srmo
cat /etc/os-release
[[ $(id -u) != 0 ]] || { echo 'Run as your desktop user; sudo is used only for installation and isolated TUN checks.'; exit 1; }
command -v pacman >/dev/null || { echo 'This test is for Omarchy / Arch Linux.'; exit 1; }
missing=()
for package in gtk3 libayatana-appindicator libcap patchelf binutils nftables iproute2 python; do
  pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
done
if ((${#missing[@]})); then sudo pacman -S --needed --noconfirm "${missing[@]}"; fi
sudo bash "$bundle/install_linux.sh" "$bundle"
systemctl --user daemon-reload
systemd-analyze --user verify /usr/lib/systemd/user/gsou.service
getcap /opt/gsou/gsou
python "$bundle/linux_core_smoke.py" /opt/gsou/lib/libsingbox.so
sudo unshare --net bash -c '
  set -euo pipefail
  ip link set lo up
  ip link add gsou-test0 type dummy
  ip addr add 192.0.2.1/24 dev gsou-test0
  ip link set gsou-test0 up
  ip route add default via 192.0.2.2 dev gsou-test0
  python "$1" /opt/gsou/lib/libsingbox.so --tun
' gsou-tun-test "$bundle/linux_core_smoke.py"
gui_log="$bundle/omarchy-gui.log"
/opt/gsou/gsou > "$gui_log" 2>&1 &
app_pid=$!
trap 'kill -TERM "$app_pid" 2>/dev/null || true' EXIT
sleep 8
if ! kill -0 "$app_pid" 2>/dev/null; then cat "$gui_log"; exit 1; fi
grep -E '^(Uid|CapEff):' "/proc/$app_pid/status"
hyprctl clients -j | python -c '
import json, sys
clients = [c for c in json.load(sys.stdin) if c.get("pid") == int(sys.argv[1])]
assert clients and any(c.get("mapped") for c in clients), "Gsou window is not mapped in Hyprland"
for c in clients:
    print("Hyprland window:", {k: c.get(k) for k in ("class", "title", "size", "mapped", "xwayland")})
' "$app_pid"
python "$bundle/check_linux_tray.py" "$app_pid"
timeout 15 /opt/gsou/gsou >> "$gui_log" 2>&1
test "$(pgrep -u "$(id -u)" -x gsou | wc -l)" = 1
kill -TERM "$app_pid"
for attempt in $(seq 1 20); do
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep .5
done
if kill -0 "$app_pid" 2>/dev/null; then echo 'SIGTERM shutdown timed out'; exit 1; fi
wait "$app_pid"
trap - EXIT
echo 'PASS: Omarchy install, native core, SOCKS, isolated TUN, Hyprland window, tray, single instance and shutdown.'
nohup /opt/gsou/gsou >> "$gui_log" 2>&1 < /dev/null &
echo "Gsou reopened for desktop inspection. Report: $report"
