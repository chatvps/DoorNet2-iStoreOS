#!/usr/bin/env bash
# Migrated from V1.7 workflow step 06: Generate build version
set -e

BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# DoorNet2 project version. Every firmware/workflow modification increments this version.
VERSION="DoorNet2-V1.1.2"
TAG="DoorNet2-V1.1.2"

echo "DOORNET2_VERSION=${VERSION}" >> "$GITHUB_ENV"
echo "DOORNET2_TAG=${TAG}" >> "$GITHUB_ENV"
echo "DOORNET2_BUILD_DATE=${BUILD_DATE}" >> "$GITHUB_ENV"

echo "========================================"
echo "VERSION=${VERSION}"
echo "TAG=${TAG}"
echo "========================================"
