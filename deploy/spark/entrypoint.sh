#!/usr/bin/env bash
set -Eeuo pipefail

seed_file() {
  local source_file="$1"
  local target_file="$2"

  if [[ ! -f "$target_file" ]]; then
    cp "$source_file" "$target_file"
  fi
}

mkdir --parents "$DSH_HOME" "$HOME"
seed_file /opt/dsh-seed/settings.yaml "$DSH_HOME/settings.yaml"
seed_file /opt/dsh-seed/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"
chown --recursive node:node /dsh-state

cd /host/chen
exec runuser --user node --preserve-environment -- \
  node /app/apps/cli/lib/bin.js web --port 3080
