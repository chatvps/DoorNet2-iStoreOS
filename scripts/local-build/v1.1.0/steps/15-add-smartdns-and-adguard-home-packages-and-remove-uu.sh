#!/usr/bin/env bash
# Migrated from V1.7 workflow step 15: Add SmartDNS and AdGuard Home packages and remove UU
set -e

echo "===== SMARTDNS / ADGUARD FROM NORMAL FEEDS ====="

./scripts/feeds install             -d y             -f             -p packages             smartdns             adguardhome

./scripts/feeds install             -d y             -f             -p luci             luci-app-smartdns

echo "===== REMOVE UU ACCELERATOR FROM ACTIVE PACKAGE TREE ====="

rm -rf             package/feeds/packages/uugamebooster             package/feeds/luci/luci-app-uugamebooster             package/feeds/istore_packages/uugamebooster             package/feeds/istore_packages/luci-app-uugamebooster             package/lean/uugamebooster             package/lean/luci-app-uugamebooster             package/doornet2/luci-app-uugamebooster             package/doornet2/uuplugin             package/doornet2/luci-app-uuplugin

echo "===== VERIFY NETWORK APP SOURCES ====="
test -n "$(find feeds/packages -type f -name Makefile -path '*/smartdns/Makefile' -print -quit)"
test -n "$(find feeds/luci -type f -name Makefile -path '*/luci-app-smartdns/Makefile' -print -quit)"
test -n "$(find feeds/packages -type f -name Makefile -path '*/adguardhome/Makefile' -print -quit)"

if find package -maxdepth 6               \( -iname '*uugamebooster*' -o -iname '*uuplugin*' \)               -print 2>/dev/null | grep -q .; then
    echo "ERROR: UU accelerator package source is still active."
    find package -maxdepth 6                 \( -iname '*uugamebooster*' -o -iname '*uuplugin*' \)                 -print 2>/dev/null || true
    exit 1
fi
