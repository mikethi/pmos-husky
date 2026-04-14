#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/pixel-mirror.conf}"
MIRROR_ROOT="${2:-$ROOT_DIR/external/pixel-mirror}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

mkdir -p "$MIRROR_ROOT"

line_no=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))

  if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  IFS='|' read -r repo_url repo_ref dest_dir extra <<< "$line"

  if [[ -n "${extra:-}" || -z "${repo_url:-}" || -z "${repo_ref:-}" || -z "${dest_dir:-}" ]]; then
    echo "Invalid config line $line_no: $line" >&2
    echo "Expected format: repo_url|ref|dest_dir" >&2
    exit 1
  fi

  if [[ "$dest_dir" = /* || "$dest_dir" == *".."* ]]; then
    echo "Invalid destination directory: $dest_dir" >&2
    exit 1
  fi

  repo_path="$MIRROR_ROOT/$dest_dir"

  if [[ ! -d "$repo_path/.git" ]]; then
    echo "Cloning $repo_url ($repo_ref) -> external/pixel-mirror/$dest_dir"
    git clone --depth 1 --branch "$repo_ref" "$repo_url" "$repo_path"
  else
    echo "Updating external/pixel-mirror/$dest_dir"
    git -C "$repo_path" remote set-url origin "$repo_url"
    git -C "$repo_path" fetch --depth 1 origin "$repo_ref"
    git -C "$repo_path" checkout -q -B "$repo_ref" "FETCH_HEAD"
    git -C "$repo_path" reset --hard -q "FETCH_HEAD"
    git -C "$repo_path" clean -fdq
  fi
done < "$CONFIG_FILE"

echo "Mirror update complete."
