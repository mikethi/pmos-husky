#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/workspaces/pmos-husky/external"
REPO_DIR="${BASE_DIR}/kernel_devices_google_shusky"
REPO_URL="https://gitlab.hentaios.com/hentaios-gs-6.x/kernel_devices_google_shusky.git"
BRANCH="Ursamoon"
ARCHIVE_URL="${REPO_URL%.git}/-/archive/${BRANCH}/kernel_devices_google_shusky-${BRANCH}.tar.gz"

mkdir -p "${BASE_DIR}"

TMP_DIR="$(mktemp -d)"
TMP_ARCHIVE="${TMP_DIR}/kernel_devices_google_shusky-${BRANCH}.tar.gz"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Downloading ${ARCHIVE_URL}..."
curl --fail --location --retry 3 --output "${TMP_ARCHIVE}" "${ARCHIVE_URL}"

echo "Extracting archive..."
tar -xzf "${TMP_ARCHIVE}" -C "${TMP_DIR}"

EXTRACTED_DIR="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "${EXTRACTED_DIR}" ]; then
  echo "Failed to locate extracted directory"
  exit 1
fi

rm -rf "${REPO_DIR}"
mv "${EXTRACTED_DIR}" "${REPO_DIR}"

echo
echo "Done. Listing dts/google:"
ls -la "${REPO_DIR}/dts/google"
