#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/sync-sources.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

declare -A REPO_CACHE

safe_dest_path() {
  local raw_dest="$1"

  if [[ "$raw_dest" = /* ]]; then
    echo "Destination must be relative: $raw_dest" >&2
    return 1
  fi

  if [[ "$raw_dest" == *".."* ]]; then
    echo "Destination cannot contain '..': $raw_dest" >&2
    return 1
  fi

  return 0
}

fetch_repo_ref() {
  local repo_url="$1"
  local repo_ref="$2"
  local cache_key="$repo_url::$repo_ref"

  if [[ -n "${REPO_CACHE[$cache_key]:-}" ]]; then
    printf '%s\n' "${REPO_CACHE[$cache_key]}"
    return 0
  fi

  local repo_dir
  repo_dir="$(mktemp -d "$TMP_ROOT/repo-XXXXXX")"

  git -C "$repo_dir" init -q
  git -C "$repo_dir" remote add origin "$repo_url"
  git -C "$repo_dir" fetch --depth 1 origin "$repo_ref" >/dev/null 2>&1 || {
    echo "Failed to fetch $repo_ref from $repo_url" >&2
    return 1
  }
  git -C "$repo_dir" checkout --detach -q FETCH_HEAD

  REPO_CACHE[$cache_key]="$repo_dir"
  printf '%s\n' "$repo_dir"
}

line_no=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))

  if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  IFS='|' read -r repo_url repo_ref source_path dest_path extra <<< "$line"

  if [[ -n "${extra:-}" || -z "${repo_url:-}" || -z "${repo_ref:-}" || -z "${source_path:-}" || -z "${dest_path:-}" ]]; then
    echo "Invalid config line $line_no: $line" >&2
    echo "Expected format: repo_url|ref|source_path|dest_path" >&2
    exit 1
  fi

  safe_dest_path "$dest_path"

  repo_checkout="$(fetch_repo_ref "$repo_url" "$repo_ref")"

  source_abs="$repo_checkout/$source_path"
  dest_abs="$ROOT_DIR/$dest_path"

  if [[ ! -e "$source_abs" ]]; then
    echo "Missing source path at line $line_no: $source_path" >&2
    exit 1
  fi

  if [[ -d "$source_abs" ]]; then
    mkdir -p "$dest_abs"
    rsync -a --delete "$source_abs/" "$dest_abs/"
    echo "Synced dir  $source_path -> $dest_path"
  else
    mkdir -p "$(dirname "$dest_abs")"
    cp -f "$source_abs" "$dest_abs"
    echo "Synced file $source_path -> $dest_path"
  fi
done < "$CONFIG_FILE"

echo "Sync complete."
