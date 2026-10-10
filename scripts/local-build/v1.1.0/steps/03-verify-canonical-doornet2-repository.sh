#!/usr/bin/env bash
# Migrated from V1.7 workflow step 03: Verify canonical DoorNet2 repository
set -e

EXPECTED_REPO="chatvps/DoorNet2-iStoreOS"

echo "Current repository:  ${GITHUB_REPOSITORY}"
echo "Expected repository: ${EXPECTED_REPO}"

if [ "${GITHUB_REPOSITORY}" != "${EXPECTED_REPO}" ]; then
    echo "ERROR: This Final workflow must run in ${EXPECTED_REPO}."
    echo "Running it in another fork would bake the wrong OPKG/release URLs into the firmware."
    exit 1
fi

echo "OK: canonical DoorNet2 repository verified."
