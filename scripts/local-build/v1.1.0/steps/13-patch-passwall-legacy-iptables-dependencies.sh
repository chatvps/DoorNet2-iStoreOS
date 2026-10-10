#!/usr/bin/env bash
# Migrated from V1.7 workflow step 13: Patch PassWall legacy iptables dependencies
set -euo pipefail

# The proven R4 DoorNet2 tree is firewall3 + legacy iptables.  It does
# not provide the newer compatibility package names
# iptables-zz-legacy / iptables-nft used by current PassWall feeds.
# The actual legacy iptables binaries are supplied by CONFIG_PACKAGE_iptables.
for mk in \
  feeds/passwall_luci/luci-app-passwall/Makefile \
  feeds/passwall2_luci/luci-app-passwall2/Makefile; do
    test -f "$mk"
    sed -i \
      -e '/^[[:space:]]*select PACKAGE_iptables-zz-legacy[[:space:]]*$/d' \
      -e '/^[[:space:]]*select PACKAGE_iptables-nft[[:space:]]*$/d' \
      "$mk"
done

if grep -RniE '^[[:space:]]*select PACKAGE_(iptables-zz-legacy|iptables-nft)[[:space:]]*$' \
    feeds/passwall_luci/luci-app-passwall/Makefile \
    feeds/passwall2_luci/luci-app-passwall2/Makefile; then
    echo "ERROR: incompatible iptables compatibility package selector remains."
    exit 1
fi

echo "OK: PassWall and PassWall2 are adapted to the proven firewall3/legacy-iptables base."
