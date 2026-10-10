#!/usr/bin/env bash
# Migrated from V1.7 workflow step 09: Add PassWall and PassWall2 feeds
set -e

echo "===== ADD OFFICIAL PASSWALL / PASSWALL2 FEEDS ====="

sed -i             -e '/^src-git passwall_packages /d'             -e '/^src-git passwall_luci /d'             -e '/^src-git passwall2_luci /d'             feeds.conf.default

{
  echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main'
  echo 'src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main'
  echo 'src-git passwall2_luci https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main'
  cat feeds.conf.default
} > feeds.conf.default.new

mv feeds.conf.default.new feeds.conf.default

echo "===== PASSWALL FEEDS ====="
head -n 10 feeds.conf.default
