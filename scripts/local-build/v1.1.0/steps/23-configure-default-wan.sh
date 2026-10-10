#!/usr/bin/env bash
# Migrated from V1.7 workflow step 23: Configure default WAN
set -e

mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/96-doornet2-wan <<'EOF'
#!/bin/sh

uci -q set network.wan='interface'
uci -q set network.wan.device='eth0'
uci -q set network.wan.proto='dhcp'
uci -q commit network

exit 0
EOF

chmod 755 files/etc/uci-defaults/96-doornet2-wan
