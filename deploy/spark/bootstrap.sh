#!/usr/bin/env bash
set -Eeuo pipefail

deployment_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(cd -- "$deployment_dir/../.." && pwd)"
runtime_dir="$deployment_dir/runtime"
release_file="$runtime_dir/release.env"

mkdir --parents "$runtime_dir"

if [[ ! -f "$runtime_dir/htpasswd" || ! -f "$runtime_dir/server.crt" || ! -f "$runtime_dir/server.key" ]]; then
  printf '%s\n' 'Proxy credentials or TLS certificate are missing; run prepare-proxy.sh first.' >&2
  exit 2
fi

if [[ ! -f "$release_file" ]]; then
  docker_gid="$(getent group docker | awk -F: '{print $3}')"
  release="$(git -C "$repository_dir" rev-parse --short=12 HEAD)"
  printf 'DSH_RELEASE=%s\nDOCKER_GID=%s\n' "$release" "$docker_gid" > "$release_file"
fi

set -a
. "$release_file"
set +a

if ! docker image inspect "deepseek-harness:spark-$DSH_RELEASE" >/dev/null 2>&1; then
  docker compose --env-file "$release_file" --project-directory "$deployment_dir" \
    --file "$deployment_dir/compose.yaml" build dsh
fi

docker compose --env-file "$release_file" --project-directory "$deployment_dir" \
  --file "$deployment_dir/compose.yaml" up --detach --no-build
