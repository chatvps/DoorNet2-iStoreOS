#!/usr/bin/env bash
# Migrated from V1.7 workflow step 04: Reproduce the proven R4 empty-config build path
set -euo pipefail

# IMPORTANT CORRECTION:
# The real-device-proven R4/V5.3.3 workflow checked out the OpenWrt
# source and did not read/copy any pre-existing .config before its
# "Configure DoorNet2 and packages" step.  `cat >> .config` therefore
# CREATED a fresh .config, and `make defconfig` was run only after all
# DoorNet2/package selections had been appended.
#
# v2.9-v3.3 copied config/doornet2.config first.  That changed the
# 6.6.66 kernel configuration/ABI and those images did not boot on the
# real DoorNet2.  v3.4 then made the opposite mistake by requiring a
# tracked top-level .config that the proven workflow never required.
R4_REFERENCE_COMMIT="9d1be44f0c1eaf3100ba122a966ff86b66354792"
R4_KERNEL_ABI="6.6.66-1-5569f718c35c6c044e99716c78d53804"
ACTUAL_SOURCE_COMMIT="$(git rev-parse HEAD)"
SOURCE_MODE="current-repo-proven-r4-boot-path"

echo "DOORNET2_SOURCE_BASELINE=${ACTUAL_SOURCE_COMMIT}" >> "$GITHUB_ENV"
echo "DOORNET2_SOURCE_REPO=${GITHUB_REPOSITORY}" >> "$GITHUB_ENV"
echo "DOORNET2_SOURCE_MODE=${SOURCE_MODE}" >> "$GITHUB_ENV"
echo "DOORNET2_R4_REFERENCE=${R4_REFERENCE_COMMIT}" >> "$GITHUB_ENV"
echo "DOORNET2_R4_KERNEL_ABI=${R4_KERNEL_ABI}" >> "$GITHUB_ENV"

echo "===== SOURCE / PROVEN R4 EMPTY-CONFIG MODE ====="
echo "Repository      : ${GITHUB_REPOSITORY}"
echo "Current commit  : ${ACTUAL_SOURCE_COMMIT}"
echo "R4 reference    : ${R4_REFERENCE_COMMIT}"
echo "R4 kernel ABI   : ${R4_KERNEL_ABI}"
echo "Mode            : ${SOURCE_MODE}"
git log -1 --oneline

test -f target/linux/rockchip/image/armv8.mk
grep -q 'define Device/embedfire_doornet2' target/linux/rockchip/image/armv8.mk

# Reproduce the proven workflow literally: start without .config.
# Never seed it from config/doornet2.config or any other vendor file.
rm -f .config
test ! -e .config

# Guard against accidentally reintroducing the known-bad path later.
echo "PROVEN_EMPTY_CONFIG_READY=1" > /tmp/doornet2-proven-empty-config

grep -RqsE '6\.6\.66|LINUX_VERSION[^=]*:?=[[:space:]]*6\.6\.66' include target 2>/dev/null || {
    echo "WARNING: 6.6.66 was not found literally in source metadata."
    echo "The generated kernel ABI audit later in this workflow is authoritative."
}
