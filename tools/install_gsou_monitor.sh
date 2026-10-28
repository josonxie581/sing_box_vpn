#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: install_gsou_monitor.sh <monitor.py> <public-key>" >&2
    exit 64
fi

monitor_source=$1
public_key_file=$2
installer_self=$0
monitor_user=gsou-monitor
monitor_path=/usr/local/libexec/gsou-monitor-status

cleanup() {
    rm -f -- "$monitor_source" "$public_key_file" "$installer_self"
}
trap cleanup EXIT HUP INT TERM

if [ "$(id -u)" -ne 0 ]; then
    echo "installer must run as root" >&2
    exit 77
fi
if [ ! -f "$monitor_source" ] || [ ! -f "$public_key_file" ]; then
    echo "installer input missing" >&2
    exit 66
fi

IFS=' ' read -r key_type key_body _comment < "$public_key_file"
case "$key_type" in
    ssh-ed25519) ;;
    *) echo "only an ed25519 monitor key is accepted" >&2; exit 65 ;;
esac
case "$key_body" in
    ''|*[!A-Za-z0-9+/=]*) echo "invalid public key" >&2; exit 65 ;;
esac

if ! id "$monitor_user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/sh --comment "Gsou read-only monitor" "$monitor_user"
    random_password=$(openssl rand -hex 32)
    password_hash=$(printf '%s' "$random_password" | openssl passwd -6 -stdin)
    unset random_password
    usermod --password "$password_hash" "$monitor_user"
    unset password_hash
fi

monitor_home=$(getent passwd "$monitor_user" | cut -d: -f6)
test -n "$monitor_home"
install -d -o root -g root -m 0755 /usr/local/libexec
install -o root -g root -m 0755 "$monitor_source" "$monitor_path"
install -d -o "$monitor_user" -g "$monitor_user" -m 0700 "$monitor_home/.ssh"

authorized_tmp=$(mktemp)
trap 'rm -f -- "$authorized_tmp"; cleanup' EXIT HUP INT TERM
printf 'restrict,command="%s" %s %s gsou-monitor\n' \
    "$monitor_path" "$key_type" "$key_body" > "$authorized_tmp"
install -o "$monitor_user" -g "$monitor_user" -m 0600 \
    "$authorized_tmp" "$monitor_home/.ssh/authorized_keys"
rm -f -- "$authorized_tmp"
trap cleanup EXIT HUP INT TERM

echo "monitor_user=$monitor_user"
echo "forced_command=$monitor_path"
echo "authorized_key=installed"
