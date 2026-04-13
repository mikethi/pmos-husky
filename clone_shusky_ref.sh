#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/workspaces/pmos-husky/external"
REPO_DIR="${BASE_DIR}/kernel_devices_google_shusky"
REPO_URL="${REPO_URL:-}"
BRANCH="Ursamoon"

if [ -z "${REPO_URL}" ]; then
  echo "Error: REPO_URL must be set to the correct kernel_devices_google_shusky repository URL." >&2
  exit 1
fi

rm -rf "${REPO_DIR}"
mv "${EXTRACTED_DIR}" "${REPO_DIR}"

echo
echo "Done. Listing dts/google:"
ls -la "${REPO_DIR}/dts/google"
