#!/usr/bin/env bash
# Migrated from V1.7 workflow step 40: Verify proven source baseline before compile
set -euo pipefail
test "$(git rev-parse HEAD)" = "${DOORNET2_SOURCE_BASELINE}"
echo "Source baseline locked: ${DOORNET2_SOURCE_BASELINE}"
echo "Source mode: ${DOORNET2_SOURCE_MODE}"
echo "R4 reference: ${DOORNET2_R4_REFERENCE}"
grep -q '^CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_embedfire_doornet2=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y$' .config
