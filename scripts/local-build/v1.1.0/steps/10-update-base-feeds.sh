#!/usr/bin/env bash
# Migrated from V1.7 workflow step 10: Update base feeds
set -e

chmod +x ./scripts/feeds
./scripts/feeds update -a
./scripts/feeds install -a -f

./scripts/feeds install             -d y             -p istore             luci-app-store

echo "===== VERIFY PASSWALL FEEDS ====="
test -f feeds/passwall_luci/luci-app-passwall/Makefile
test -f feeds/passwall2_luci/luci-app-passwall2/Makefile
test -d feeds/passwall_packages

./scripts/feeds install             -d y             -p passwall_luci             luci-app-passwall

./scripts/feeds install             -d y             -p passwall2_luci             luci-app-passwall2

grep -nE             'PKG_NAME:=luci-app-passwall|PKG_VERSION|LUCI_DEPENDS'             feeds/passwall_luci/luci-app-passwall/Makefile             | head -20

grep -nE             'PKG_NAME:=luci-app-passwall2|PKG_VERSION|LUCI_DEPENDS|Basic_Core'             feeds/passwall2_luci/luci-app-passwall2/Makefile             | head -30
