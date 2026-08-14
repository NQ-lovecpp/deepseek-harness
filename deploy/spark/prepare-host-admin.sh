#!/usr/bin/env bash
set -Eeuo pipefail

deployment_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime_dir="$deployment_dir/runtime"
token_file="$runtime_dir/systemctl-proxy.token"

mkdir --parents "$runtime_dir"
umask 077

if [[ ! -s "$token_file" ]]; then
  openssl rand -hex 32 > "$token_file"
fi

chmod 0600 "$token_file"
