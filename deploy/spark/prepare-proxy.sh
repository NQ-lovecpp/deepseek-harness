#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${NGINX_AUTH_PASSWORD:-}" ]]; then
  printf '%s\n' 'Set NGINX_AUTH_PASSWORD before preparing the proxy.' >&2
  exit 2
fi

deployment_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime_dir="$deployment_dir/runtime"

mkdir --parents "$runtime_dir"
umask 077

password_hash="$(printf '%s' "$NGINX_AUTH_PASSWORD" | openssl passwd -apr1 -stdin)"
printf 'chen:%s\n' "$password_hash" > "$runtime_dir/htpasswd"

if [[ ! -f "$runtime_dir/server.crt" || ! -f "$runtime_dir/server.key" ]]; then
  openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$runtime_dir/server.key" \
    -out "$runtime_dir/server.crt" \
    -sha256 \
    -days 825 \
    -subj '/CN=117.72.15.209' \
    -addext 'subjectAltName=IP:117.72.15.209'
fi

chmod 0600 "$runtime_dir/htpasswd" "$runtime_dir/server.key"
chmod 0644 "$runtime_dir/server.crt"
