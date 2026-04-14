#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/passive-build.conf}"
STATE_DIR="$ROOT_DIR/.state"
CHECKSUM_FILE="$STATE_DIR/passive-sync.sha256"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

SYNC_CONFIG="${SYNC_CONFIG:-sync-sources.conf}"
PRE_SYNC_COMMAND="${PRE_SYNC_COMMAND:-}"
POLL_SECONDS="${POLL_SECONDS:-900}"
BUILD_COMMAND="${BUILD_COMMAND:-echo Set BUILD_COMMAND in passive-build.conf}"
BUILD_ON_CHANGE_ONLY="${BUILD_ON_CHANGE_ONLY:-true}"
INITIAL_BUILD="${INITIAL_BUILD:-false}"

if [[ "$POLL_SECONDS" =~ [^0-9] ]] || [[ "$POLL_SECONDS" -lt 30 ]]; then
  echo "POLL_SECONDS must be an integer >= 30" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/$SYNC_CONFIG" ]]; then
  echo "SYNC_CONFIG not found: $ROOT_DIR/$SYNC_CONFIG" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

collect_dest_paths() {
  awk -F'|' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    NF >= 4 { print $4 }
  ' "$ROOT_DIR/$SYNC_CONFIG"
}

compute_sync_checksum() {
  local tmp_manifest
  tmp_manifest="$(mktemp)"

  while IFS= read -r dest_path; do
    [[ -z "$dest_path" ]] && continue

    local abs_path
    abs_path="$ROOT_DIR/$dest_path"

    if [[ -d "$abs_path" ]]; then
      find "$abs_path" -type f -print0 | sort -z | while IFS= read -r -d '' f; do
        local sum rel
        sum="$(sha256sum "$f" | awk '{print $1}')"
        rel="${f#"$ROOT_DIR/"}"
        printf '%s  %s\n' "$sum" "$rel"
      done >> "$tmp_manifest"
    elif [[ -f "$abs_path" ]]; then
      local sum
      sum="$(sha256sum "$abs_path" | awk '{print $1}')"
      printf '%s  %s\n' "$sum" "$dest_path" >> "$tmp_manifest"
    else
      printf 'missing  %s\n' "$dest_path" >> "$tmp_manifest"
    fi
  done < <(collect_dest_paths)

  if [[ ! -s "$tmp_manifest" ]]; then
    # Keep deterministic output when sync config has no active entries.
    printf 'empty-sync-config\n' >> "$tmp_manifest"
  fi

  local digest
  digest="$(sha256sum "$tmp_manifest" | awk '{print $1}')"
  rm -f "$tmp_manifest"
  printf '%s\n' "$digest"
}

run_build() {
  log "Running build command"
  bash -lc "cd \"$ROOT_DIR\" && $BUILD_COMMAND"
  log "Build command finished"
}

should_build_this_round() {
  local current_checksum previous_checksum
  current_checksum="$1"
  previous_checksum="$2"

  if [[ "$INITIAL_BUILD" == "true" && ! -f "$CHECKSUM_FILE" ]]; then
    return 0
  fi

  if [[ "$BUILD_ON_CHANGE_ONLY" == "true" ]]; then
    [[ "$current_checksum" != "$previous_checksum" ]]
    return
  fi

  return 0
}

log "Passive build loop started"
log "Sync config: $SYNC_CONFIG"
log "Poll interval: ${POLL_SECONDS}s"

while true; do
  if [[ -n "$PRE_SYNC_COMMAND" ]]; then
    log "Running pre-sync command"
    bash -lc "cd \"$ROOT_DIR\" && $PRE_SYNC_COMMAND"
  fi

  log "Starting sync"
  "$ROOT_DIR/sync-sources.sh" "$ROOT_DIR/$SYNC_CONFIG"

  current_checksum="$(compute_sync_checksum)"
  previous_checksum=""
  if [[ -f "$CHECKSUM_FILE" ]]; then
    previous_checksum="$(cat "$CHECKSUM_FILE")"
  fi

  if should_build_this_round "$current_checksum" "$previous_checksum"; then
    run_build
  else
    log "No synced source changes detected, skipping build"
  fi

  printf '%s\n' "$current_checksum" > "$CHECKSUM_FILE"
  log "Sleeping for ${POLL_SECONDS}s"
  sleep "$POLL_SECONDS"
done
