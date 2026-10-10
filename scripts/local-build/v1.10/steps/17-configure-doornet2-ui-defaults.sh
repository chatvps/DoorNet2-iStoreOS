#!/usr/bin/env bash
# Migrated from V1.7 workflow step 17: Configure DoorNet2 UI defaults
set -e

mkdir -p \
  files/etc/uci-defaults \
  files/etc/config

cat > files/etc/uci-defaults/95-doornet2-ui <<'EOF'
#!/bin/sh

# DoorNet2 R34 UI policy:
# Design default + QuickStart home, with Argon/Bootstrap recovery.

uci -q set luci.themes.Design='/luci-static/design'
uci -q set luci.themes.Argon='/luci-static/argon'
uci -q set luci.main.mediaurlbase='/luci-static/design'
uci -q set luci.main.lang='zh_cn'
uci -q commit luci

if [ "$(uci -q get system.@system[0].hostname)" = "OpenWrt" ]; then
    uci -q set system.@system[0].hostname='DoorNet2'
    uci -q commit system
fi

rm -rf \
  /tmp/luci-indexcache \
  /tmp/luci-modulecache \
  /tmp/luci-templatecache

exit 0
EOF

chmod 755 files/etc/uci-defaults/95-doornet2-ui
sh -n files/etc/uci-defaults/95-doornet2-ui

cat > files/etc/config/design <<'EOF'
config global
        option mode 'dark'
        option navbar 'display'
        option navbar_proxy 'passwall'
EOF

echo "===== FINAL UI DEFAULTS ====="
cat files/etc/uci-defaults/95-doornet2-ui
cat files/etc/config/design
