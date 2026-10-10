#!/usr/bin/env bash
# Migrated from V1.7 workflow step 16: Add QuickStart and DoorNet2 UI themes
set -e

echo "===== ADD QUICKSTART FEEDS ====="

grep -q '^src-git nas ' feeds.conf.default || \
  echo 'src-git nas https://github.com/linkease/nas-packages.git;master' \
  >> feeds.conf.default

grep -q '^src-git nas_luci ' feeds.conf.default || \
  echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' \
  >> feeds.conf.default

./scripts/feeds update nas nas_luci

./scripts/feeds install \
  -d y \
  -p nas \
  quickstart

./scripts/feeds install \
  -d y \
  -p nas_luci \
  luci-app-quickstart

echo "===== ADD DESIGN THEME (DEFAULT) ====="

mkdir -p package/lean

rm -rf \
  package/lean/luci-theme-design \
  package/lean/luci-theme-argon \
  package/lean/luci-app-argon-config

# Design main is the Lua/LEDE branch and matches this DoorNet2 tree.
git clone \
  --depth 1 \
  --branch main \
  https://github.com/0x676e67/luci-theme-design.git \
  package/lean/luci-theme-design

# Keep Argon as a recovery/fallback theme only.
git clone \
  --depth 1 \
  https://github.com/jerrykuku/luci-theme-argon.git \
  package/lean/luci-theme-argon

git clone \
  --depth 1 \
  https://github.com/jerrykuku/luci-app-argon-config.git \
  package/lean/luci-app-argon-config

echo "===== VERIFY QUICKSTART / DESIGN / RECOVERY THEMES ====="

test -f feeds/nas/network/services/quickstart/Makefile
test -f feeds/nas_luci/luci/luci-app-quickstart/Makefile

test -f package/lean/luci-theme-design/Makefile
test -f package/lean/luci-theme-design/luasrc/view/themes/design/header.htm
test -f package/lean/luci-theme-design/htdocs/luci-static/design/css/style.css

test -f package/lean/luci-theme-argon/Makefile
test -f package/lean/luci-app-argon-config/Makefile

grep -nE \
  'PKG_NAME:=quickstart|PKG_VERSION|DEPENDS' \
  feeds/nas/network/services/quickstart/Makefile \
  | head -20

grep -nE \
  'LUCI_TITLE|LUCI_DEPENDS|PKG_VERSION' \
  feeds/nas_luci/luci/luci-app-quickstart/Makefile

echo "===== PATCH DESIGN HOME SHORTCUT TO QUICKSTART ====="

DESIGN_HEADER="package/lean/luci-theme-design/luasrc/view/themes/design/header.htm"

sed -i \
  's#/cgi-bin/luci/admin/status/overview#/cgi-bin/luci/admin/quickstart/#g' \
  "$DESIGN_HEADER"

grep -n '/cgi-bin/luci/admin/quickstart/' "$DESIGN_HEADER"
