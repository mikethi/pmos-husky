#!/usr/bin/env bash
# bare-metal-install.sh — Interactive bare-metal helper for Google Pixel (Husky)
# Reads device identity from bare-metal-husky.conf when present.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${ROOT_DIR}/bare-metal-husky.conf"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "Required command not found: $1"
}

prompt_dir() {
  local label="$1" default="$2" result
  read -rp "${label} [${default}]: " result
  result="${result:-$default}"
  printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Load optional device config
# ---------------------------------------------------------------------------

DEVICE_CODENAME="husky"
BUILD_FINGERPRINT=""
if [[ -f "$CONF" ]]; then
  # shellcheck source=/dev/null
  source "$CONF"
fi

# ---------------------------------------------------------------------------
# Section 20: Recursive IMG / Archive Extraction
# ---------------------------------------------------------------------------

# Print a summary line for a given file type.
_ext_label() {
  local f="$1"
  case "${f,,}" in
    *.zip)           printf 'ZIP archive'        ;;
    *.tar.gz|*.tgz)  printf 'TAR+GZ archive'    ;;
    *.tar.bz2|*.tbz2) printf 'TAR+BZ2 archive'  ;;
    *.tar.xz|*.txz)  printf 'TAR+XZ archive'    ;;
    *.tar.lz4)       printf 'TAR+LZ4 archive'   ;;
    *.tar.zst)       printf 'TAR+ZST archive'   ;;
    *.tar)           printf 'TAR archive'        ;;
    *.gz)            printf 'GZ compressed'      ;;
    *.bz2)           printf 'BZ2 compressed'     ;;
    *.xz)            printf 'XZ compressed'      ;;
    *.lz4)           printf 'LZ4 compressed'     ;;
    *.zst)           printf 'ZST compressed'     ;;
    *.7z)            printf '7-Zip archive'      ;;
    *.img.gz)        printf 'Compressed IMG'     ;;
    *.img.lz4)       printf 'LZ4-compressed IMG' ;;
    *.img.xz)        printf 'XZ-compressed IMG'  ;;
    *.img.zst)       printf 'ZST-compressed IMG' ;;
    *.simg)          printf 'Sparse IMG'         ;;
    *.payload|payload.bin) printf 'OTA payload'  ;;
    *)               printf 'Unknown'            ;;
  esac
}

# Return 0 if the file looks extractable/decryptable, 1 otherwise.
_is_extractable() {
  local f="${1,,}"
  case "$f" in
    *.zip|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz| \
    *.tar.lz4|*.tar.zst|*.tar|*.gz|*.bz2|*.xz|*.lz4|*.zst| \
    *.7z|*.img.gz|*.img.lz4|*.img.xz|*.img.zst|*.simg| \
    *payload.bin|*.payload) return 0 ;;
  esac
  return 1
}

# Extract a single file into dest_dir.  Returns 0 on success.
_extract_file() {
  local src="$1" dest_dir="$2"
  local fname base
  fname="$(basename "$src")"
  base="${fname%.*}"    # strip last extension for plain compressed files

  mkdir -p "$dest_dir"

  case "${fname,,}" in
    *.zip)
      require_cmd unzip
      unzip -q "$src" -d "$dest_dir"
      ;;
    *.tar.gz|*.tgz)
      require_cmd tar
      tar -xzf "$src" -C "$dest_dir"
      ;;
    *.tar.bz2|*.tbz2)
      require_cmd tar
      tar -xjf "$src" -C "$dest_dir"
      ;;
    *.tar.xz|*.txz)
      require_cmd tar
      tar -xJf "$src" -C "$dest_dir"
      ;;
    *.tar.lz4)
      require_cmd tar; require_cmd lz4
      tar -x --use-compress-program=lz4 -f "$src" -C "$dest_dir"
      ;;
    *.tar.zst)
      require_cmd tar; require_cmd zstd
      tar -x --use-compress-program=zstd -f "$src" -C "$dest_dir"
      ;;
    *.tar)
      require_cmd tar
      tar -xf "$src" -C "$dest_dir"
      ;;
    *.gz)
      require_cmd gzip
      gzip -dk "$src" --stdout > "${dest_dir}/${base}"
      ;;
    *.bz2)
      require_cmd bzip2
      bzip2 -dk "$src" --stdout > "${dest_dir}/${base}"
      ;;
    *.xz)
      require_cmd xz
      xz -dk "$src" --stdout > "${dest_dir}/${base}"
      ;;
    *.lz4)
      require_cmd lz4
      lz4 -d "$src" "${dest_dir}/${base}"
      ;;
    *.zst)
      require_cmd zstd
      zstd -d "$src" -o "${dest_dir}/${base}"
      ;;
    *.7z)
      require_cmd 7z
      7z x "$src" -o"$dest_dir" -y -bd
      ;;
    *.img.gz)
      require_cmd gzip
      gzip -dk "$src" --stdout > "${dest_dir}/${fname%.gz}"
      ;;
    *.img.lz4)
      require_cmd lz4
      lz4 -d "$src" "${dest_dir}/${fname%.lz4}"
      ;;
    *.img.xz)
      require_cmd xz
      xz -dk "$src" --stdout > "${dest_dir}/${fname%.xz}"
      ;;
    *.img.zst)
      require_cmd zstd
      zstd -d "$src" -o "${dest_dir}/${fname%.zst}"
      ;;
    *.simg)
      require_cmd simg2img
      simg2img "$src" "${dest_dir}/${fname%.simg}.img"
      ;;
    *payload.bin|*.payload)
      if command -v payload-dumper-go &>/dev/null; then
        payload-dumper-go -output "$dest_dir" "$src"
      elif command -v payload_dumper &>/dev/null; then
        python3 "$(command -v payload_dumper)" --out "$dest_dir" "$src"
      else
        err "  No payload dumper found (payload-dumper-go or payload_dumper). Skipping: $fname"
        return 1
      fi
      ;;
    *)
      err "  No handler for: $fname"
      return 1
      ;;
  esac
}

# Recursively scan a directory, extract everything extractable, then re-scan
# extracted folders until nothing new is found.
_recursive_extract() {
  local scan_dir="$1"
  local depth="${2:-0}"
  local indent
  indent="$(printf '%*s' $((depth * 2)) '')"

  local found=0

  # Collect files in this directory (non-recursive; we'll descend manually).
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    _is_extractable "$f" || continue

    local label
    label="$(_ext_label "$f")"
    local fname dest_subdir base_no_ext
    fname="$(basename "$f")"
    # Strip only the final extension so multi-extension names like
    # system.img.gz become system.img_extracted/ (not system_extracted/).
    base_no_ext="${fname%.*}"
    dest_subdir="$(dirname "$f")/${base_no_ext}_extracted"

    printf '%s  -> [%s] %s\n' "$indent" "$label" "$fname"

    if _extract_file "$f" "$dest_subdir"; then
      printf '%s     Extracted to: %s\n' "$indent" "$dest_subdir"
      found=1
      # Recurse into the newly extracted folder.
      _recursive_extract "$dest_subdir" $((depth + 1))
    else
      printf '%s     Skipped (extraction failed or no tool available).\n' "$indent"
    fi
  done < <(find "$scan_dir" -maxdepth 1 -type f -print0 | sort -z)

  # Also descend into any pre-existing subdirectories (including the "e" folder
  # or any folder that was already there before this pass).
  while IFS= read -r -d '' d; do
    [[ "$d" == "$scan_dir" ]] && continue
    printf '%s  [dir] Scanning subfolder: %s\n' "$indent" "$(basename "$d")"
    _recursive_extract "$d" $((depth + 1))
  done < <(find "$scan_dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

  if [[ $found -eq 0 && $depth -eq 0 ]]; then
    log "No extractable files found in: $scan_dir"
  fi
}

option_20_img_extract() {
  echo
  echo "=== IMG / Archive Recursive Extraction ==="
  echo
  echo "This option will:"
  echo "  1. Scan a source folder for all archive and image files."
  echo "  2. Extract each one into a sibling '<name>_extracted' folder."
  echo "  3. Recursively scan every extracted folder (including sub-folders)"
  echo "     for additional files that need extraction or decryption."
  echo "  4. Repeat until no more extractable files are found."
  echo

  local src_dir
  src_dir="$(prompt_dir 'Source folder to scan' "${HOME}/Downloads")"

  if [[ ! -d "$src_dir" ]]; then
    err "Directory not found: $src_dir"
    return 1
  fi

  log "Starting recursive extraction from: $src_dir"
  _recursive_extract "$src_dir" 0
  log "Recursive extraction complete."
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

show_menu() {
  echo
  echo "========================================"
  echo "  Bare-Metal Install Helper — ${DEVICE_CODENAME}"
  echo "========================================"
  echo
  echo "  --- Device Info ---"
  echo "   1) Show device/build info"
  echo "   2) Check fastboot connection"
  echo "   3) Check ADB connection"
  echo
  echo "  --- Fastboot Operations ---"
  echo "   4) Reboot to bootloader"
  echo "   5) Reboot to recovery"
  echo "   6) Reboot to system"
  echo "   7) Unlock bootloader"
  echo "   8) Lock bootloader"
  echo
  echo "  --- Partition Flash ---"
  echo "   9) Flash boot image"
  echo "  10) Flash vendor_boot image"
  echo "  11) Flash dtbo image"
  echo "  12) Flash recovery image"
  echo "  13) Flash system image"
  echo "  14) Flash userdata image"
  echo "  15) Flash all (from factory zip)"
  echo
  echo "  --- Verification ---"
  echo "  16) Verify partition checksums"
  echo "  17) Dump current partition table"
  echo "  18) Read build fingerprint from device"
  echo "  19) Compare fingerprint to conf"
  echo
  echo "  --- IMG Extraction ---"
  echo "  20) Recursive archive / image extraction"
  echo
  echo "   0) Exit"
  echo
}

# ---------------------------------------------------------------------------
# Option stubs (1-19)
# ---------------------------------------------------------------------------

option_1()  {
  echo
  echo "Device codename : ${DEVICE_CODENAME}"
  echo "Build fingerprint: ${BUILD_FINGERPRINT:-<not set>}"
  echo "Config file     : ${CONF}"
}
option_2()  { require_cmd fastboot; fastboot devices; }
option_3()  { require_cmd adb;     adb devices;     }
option_4()  { require_cmd fastboot; log "Rebooting to bootloader..."; fastboot reboot bootloader; }
option_5()  { require_cmd fastboot; log "Rebooting to recovery...";   fastboot reboot recovery;   }
option_6()  { require_cmd fastboot; log "Rebooting to system...";     fastboot reboot;             }
option_7()  {
  require_cmd fastboot
  read -rp "Unlock bootloader? This wipes data. Type YES to confirm: " ans
  [[ "$ans" == "YES" ]] || { echo "Aborted."; return; }
  fastboot flashing unlock
}
option_8()  {
  require_cmd fastboot
  read -rp "Lock bootloader? Type YES to confirm: " ans
  [[ "$ans" == "YES" ]] || { echo "Aborted."; return; }
  fastboot flashing lock
}

_flash_img() {
  local partition="$1" default_name="$2"
  require_cmd fastboot
  local img
  img="$(prompt_dir "Path to ${partition} image" "${ROOT_DIR}/${default_name}")"
  [[ -f "$img" ]] || die "Image not found: $img"
  log "Flashing ${partition} with ${img}..."
  fastboot flash "$partition" "$img"
  log "Done."
}

option_9()  { _flash_img boot        boot.img;        }
option_10() { _flash_img vendor_boot vendor_boot.img; }
option_11() { _flash_img dtbo        dtbo.img;        }
option_12() { _flash_img recovery    recovery.img;    }
option_13() { _flash_img system      system.img;      }
option_14() { _flash_img userdata    userdata.img;    }
option_15() {
  require_cmd fastboot
  local zip
  zip="$(prompt_dir "Path to factory zip" "${ROOT_DIR}/factory.zip")"
  [[ -f "$zip" ]] || die "Factory zip not found: $zip"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN
  log "Extracting factory zip..."
  unzip -q "$zip" -d "$tmp_dir"
  local flash_script
  flash_script="$(find "$tmp_dir" -maxdepth 2 -name 'flash-all.sh' | head -n 1)"
  [[ -n "$flash_script" ]] || die "flash-all.sh not found inside zip."
  log "Running flash-all.sh..."
  bash "$flash_script"
}

option_16() {
  log "Partition checksum verification is device-specific."
  echo "Refer to bare-metal-husky.conf for expected partition list."
}
option_17() { require_cmd fastboot; fastboot getvar all 2>&1 | grep -i partition || true; }
option_18() { require_cmd adb; adb shell getprop ro.build.fingerprint; }
option_19() {
  require_cmd adb
  local live expected
  live="$(adb shell getprop ro.build.fingerprint 2>/dev/null || echo '<adb unavailable>')"
  expected="${BUILD_FINGERPRINT:-<not configured>}"
  echo "Live fingerprint    : ${live}"
  echo "Expected fingerprint: ${expected}"
  if [[ "$live" == "$expected" ]]; then
    echo "MATCH"
  else
    echo "MISMATCH"
  fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
  while true; do
    show_menu
    read -rp "Select option: " choice
    case "$choice" in
      1)  option_1  ;;
      2)  option_2  ;;
      3)  option_3  ;;
      4)  option_4  ;;
      5)  option_5  ;;
      6)  option_6  ;;
      7)  option_7  ;;
      8)  option_8  ;;
      9)  option_9  ;;
      10) option_10 ;;
      11) option_11 ;;
      12) option_12 ;;
      13) option_13 ;;
      14) option_14 ;;
      15) option_15 ;;
      16) option_16 ;;
      17) option_17 ;;
      18) option_18 ;;
      19) option_19 ;;
      20) option_20_img_extract ;;
      0)  log "Exiting."; exit 0 ;;
      *)  echo "Invalid option: $choice" ;;
    esac
  done
}

main
