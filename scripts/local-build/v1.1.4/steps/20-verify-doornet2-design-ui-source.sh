#!/usr/bin/env bash
# Migrated from V1.7 workflow step 20: Verify DoorNet2 Design UI source
set -e

echo "===== VERIFY FINAL DESIGN UI SOURCE ====="

test -f package/lean/luci-theme-design/Makefile
test -f package/lean/luci-theme-design/luasrc/view/themes/design/header.htm
test -f package/lean/luci-theme-design/htdocs/luci-static/design/css/style.css

grep -q \
  '/cgi-bin/luci/admin/quickstart/' \
  package/lean/luci-theme-design/luasrc/view/themes/design/header.htm

test -f files/etc/config/design
grep -q "option mode 'dark'" files/etc/config/design
grep -q "option navbar_proxy 'passwall'" files/etc/config/design

test -x files/etc/uci-defaults/95-doornet2-ui
grep -q "mediaurlbase='/luci-static/design'" \
  files/etc/uci-defaults/95-doornet2-ui
