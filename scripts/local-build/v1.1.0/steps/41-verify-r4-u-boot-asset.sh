#!/usr/bin/env bash
# Migrated from V1.7 workflow step 41: Verify R4 U-Boot asset
set -euo pipefail

ASSET="${GITHUB_WORKSPACE}/r4.bin.gz"
EXPECTED_PATCH_SHA="6cd741e71a65802062ecf134d1dd5f33269c02ccea90a203231a84bdcc7d228a"

test -f "$ASSET" || {
    echo "ERROR: proven R4 U-Boot asset missing: $ASSET"
    exit 1
}

gzip -t "$ASSET"

PATCH_BIN="$(mktemp)"
trap 'rm -f "$PATCH_BIN"' EXIT
gzip -dc "$ASSET" > "$PATCH_BIN"

test "$(stat -c%s "$PATCH_BIN")" -eq $((4 * 1024 * 1024)) || {
    echo "ERROR: proven R4 U-Boot region must be exactly 4 MiB."
    exit 1
}

echo "${EXPECTED_PATCH_SHA}  ${PATCH_BIN}" | sha256sum -c -
echo "OK: proven R4 U-Boot asset verified."
