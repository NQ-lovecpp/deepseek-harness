#!/usr/bin/env bash
set -Eeuo pipefail

deployment_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(cd -- "$deployment_dir/../.." && pwd)"
runtime_dir="$deployment_dir/runtime"
release_file="$runtime_dir/release.env"
previous_release_file="$runtime_dir/release.previous.env"
candidate_release_file="$runtime_dir/release.candidate.env"
upstream_base_file="$runtime_dir/upstream-base"
log_file="$runtime_dir/update.log"

mkdir --parents "$runtime_dir"
exec >>"$log_file" 2>&1
exec 9>"$runtime_dir/update.lock"

if ! flock --nonblock 9; then
  printf '%s %s\n' "$(date --iso-8601=seconds)" 'another update is already running'
  exit 0
fi

rollback() {
  local previous_commit="$1"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "rolling back to $previous_commit"
  git -C "$repository_dir" reset --hard "$previous_commit"
  cp "$previous_release_file" "$release_file"
  docker compose --env-file "$release_file" --project-directory "$deployment_dir" --file "$deployment_dir/compose.yaml" \
    up --detach --no-build --force-recreate dsh access-proxy
}

healthy() {
  local deadline=$((SECONDS + 180))
  until curl --fail --silent --show-error http://127.0.0.1:3080/ >/dev/null; do
    if (( SECONDS >= deadline )); then
      return 1
    fi
    sleep 5
  done
}

if [[ ! -f "$release_file" ]]; then
  printf '%s\n' 'No active release exists. Start deepseek-harness.service before enabling updates.'
  exit 2
fi

if ! git -C "$repository_dir" diff --quiet || ! git -C "$repository_dir" diff --cached --quiet; then
  printf '%s\n' 'Refusing update because the deployment checkout has uncommitted changes.'
  exit 2
fi

previous_commit="$(git -C "$repository_dir" rev-parse HEAD)"
cp "$release_file" "$previous_release_file"

previous_upstream=""
if [[ -f "$upstream_base_file" ]]; then
  previous_upstream="$(<"$upstream_base_file")"
elif git -C "$repository_dir" rev-parse --verify --quiet refs/remotes/upstream/master >/dev/null; then
  previous_upstream="$(git -C "$repository_dir" rev-parse refs/remotes/upstream/master)"
fi

printf '%s %s\n' "$(date --iso-8601=seconds)" 'fetching upstream/master'
git_proxy="${DSH_GIT_HTTPS_PROXY:-}"
if [[ -n "$git_proxy" ]]; then
  printf '%s %s\n' "$(date --iso-8601=seconds)" "using configured HTTPS proxy for upstream fetch"
fi
timeout --preserve-status 180 \
  env GIT_TERMINAL_PROMPT=0 HTTPS_PROXY="$git_proxy" HTTP_PROXY="$git_proxy" \
  git -C "$repository_dir" fetch --depth=1 upstream master

if [[ -z "$previous_upstream" ]]; then
  previous_upstream="$(git -C "$repository_dir" merge-base HEAD FETCH_HEAD || true)"
fi

if [[ -z "$previous_upstream" ]]; then
  printf '%s\n' 'Update stopped because no prior upstream base is available; active service was not changed.'
  exit 1
fi

if ! git -C "$repository_dir" rebase --onto FETCH_HEAD "$previous_upstream"; then
  git -C "$repository_dir" rebase --abort
  printf '%s\n' 'Update stopped because upstream rebase conflicted; active service was not changed.'
  exit 1
fi

candidate_release="$(git -C "$repository_dir" rev-parse --short=12 HEAD)"
docker_gid="$(getent group docker | awk -F: '{print $3}')"
printf 'DSH_RELEASE=%s\nDOCKER_GID=%s\n' "$candidate_release" "$docker_gid" > "$candidate_release_file"

if ! docker compose --env-file "$candidate_release_file" --project-directory "$deployment_dir" \
  --file "$deployment_dir/compose.yaml" build dsh; then
  rollback "$previous_commit"
  exit 1
fi

cp "$candidate_release_file" "$release_file"
if ! docker compose --env-file "$release_file" --project-directory "$deployment_dir" \
  --file "$deployment_dir/compose.yaml" \
  up --detach --no-build --force-recreate dsh; then
  rollback "$previous_commit"
  exit 1
fi

if ! healthy; then
  rollback "$previous_commit"
  exit 1
fi

docker compose --env-file "$release_file" --project-directory "$deployment_dir" \
  --file "$deployment_dir/compose.yaml" \
  up --detach --no-build access-proxy
printf '%s\n' "$(git -C "$repository_dir" rev-parse FETCH_HEAD)" > "$upstream_base_file"
printf '%s %s\n' "$(date --iso-8601=seconds)" "updated successfully to $candidate_release"
