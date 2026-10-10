#!/usr/bin/env bash
# Migrated from V1.7 workflow step 26: Configure GitHub OPKG feed
set -e

mkdir -p files/etc/opkg

cat > files/etc/opkg/distfeeds.conf <<EOF
src/gz openwrt_core https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/targets/rockchip/armv8/packages
src/gz openwrt_base https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/base
src/gz openwrt_istore https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/istore
src/gz openwrt_luci https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/luci
src/gz openwrt_packages https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/packages
src/gz openwrt_routing https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/routing
src/gz openwrt_telephony https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/telephony
src/gz doornet2_passwall_luci https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/passwall_luci
src/gz doornet2_passwall2_luci https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/passwall2_luci
src/gz doornet2_passwall_packages https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/opkg-feed/packages/aarch64_generic/passwall_packages
EOF
