#!/usr/bin/env bash
set -euo pipefail

[[ $(uname -s) == Linux ]] || { echo 'Build the Linux core on Linux.' >&2; exit 1; }
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-"$project_dir/build/linux-core/libsingbox.so"}
mkdir -p -- "$(dirname -- "$output")"
output=$(realpath -m -- "$output")
work_dir="$project_dir/build/linux-core"
mkdir -p -- "$work_dir"
version=$(tr -d '\r\n' < "$project_dir/sing-box-version.txt")
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][a-zA-Z0-9.]+)?$ ]] || {
  echo 'Invalid sing-box-version.txt' >&2; exit 1;
}

for command in go git cc; do
  command -v "$command" >/dev/null || { echo "Missing build tool: $command" >&2; exit 1; }
done

# Do not checkout or modify the user's sibling sing-box working tree.
source_dir=${SING_BOX_SOURCE:-"$work_dir/sing-box-$version"}
if [[ -z ${SING_BOX_SOURCE:-} ]]; then
  if [[ ! -d $source_dir ]]; then
    git clone --depth 1 --branch "$version" https://github.com/SagerNet/sing-box.git "$source_dir"
  fi
  [[ $(git -C "$source_dir" describe --tags --exact-match HEAD) == "$version" ]] || {
    echo "Core checkout does not match $version: $source_dir" >&2; exit 1;
  }
  [[ -z $(git -C "$source_dir" status --porcelain) ]] || {
    echo "Core checkout has local edits. Set SING_BOX_SOURCE explicitly to use them." >&2; exit 1;
  }
fi
source_dir=$(realpath -- "$source_dir")
[[ -f $source_dir/go.mod ]] || { echo "Missing core source: $source_dir" >&2; exit 1; }

cp -- "$project_dir/native/go.mod" "$work_dir/native.mod"
cp -- "$project_dir/native/go.sum" "$work_dir/native.sum"
cd -- "$project_dir/native"
export CGO_ENABLED=1 GOOS=linux
case $(uname -m) in
  x86_64) export GOARCH=amd64 ;;
  aarch64|arm64) export GOARCH=arm64 ;;
  *) echo 'Supported build hosts: Linux x86_64 / aarch64.' >&2; exit 1 ;;
esac
go mod edit -modfile="$work_dir/native.mod" "-replace=github.com/sagernet/sing-box=$source_dir"
tags=with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_gvisor,with_grpc
go build -mod=readonly -modfile="$work_dir/native.mod" -tags "$tags" -trimpath \
  -ldflags "-s -w -buildid= -X github.com/sagernet/sing-box/constant.Version=${version#v}" \
  -buildmode=c-shared -o "$output" .
echo "Built $output"
