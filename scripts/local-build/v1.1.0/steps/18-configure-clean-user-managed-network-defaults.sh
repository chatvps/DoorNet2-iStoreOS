#!/usr/bin/env bash
# Migrated from V1.7 workflow step 18: Configure clean user-managed network defaults
set -e

echo "===== REMOVE OLD BAKED-IN NETWORK APP CONFIGURATION ====="

# The repository may contain settings from an older DoorNet2 image.
# Do not bake those settings into a new clean image.  Let each package
# install its own stock configuration, then apply only a one-time
# disabled-by-default policy below.
rm -f \
  files/etc/config/passwall \
  files/etc/config/passwall2 \
  files/etc/config/passwall_server \
  files/etc/config/passwall2_server \
  files/etc/config/smartdns \
  files/etc/config/adguardhome \
  files/etc/config/dhcp \
  files/etc/adguardhome.yaml

rm -rf \
  files/etc/passwall \
  files/etc/passwall2 \
  files/etc/smartdns

# The historical DoorNet2 source tree may already contain a modified
# dnsmasq template that forces 127.0.0.1:3053 + noresolv=1.  The Final
# user-managed image must not ship that chain because AdGuard/SmartDNS
# are intentionally OFF on a clean install.  Scrub only files which
# actually contain that exact old loopback target.
echo "===== SCRUB LEGACY FORCED DNSMASQ CHAIN ====="
while IFS= read -r dns_file; do
    [ -f "$dns_file" ] || continue
    echo "Sanitizing: $dns_file"
    sed -i \
      -e '/127\.0\.0\.1#3053/d' \
      -e "/option[[:space:]]\+noresolv[[:space:]]\+['\"]\?1['\"]\?/d" \
      "$dns_file"
done < <(
    grep -RIl --exclude-dir=.git '127.0.0.1#3053' \
      package feeds target config 2>/dev/null || true
)

# Remove old DoorNet2 automation which could silently rewrite a user's
# DNS/proxy choices on later boots.
rm -f \
  files/etc/init.d/doornet2-dns-chain \
  files/etc/init.d/passwall-delay \
  files/etc/init.d/passwall2-delay \
  files/etc/uci-defaults/96-doornet2-passwall-shunt \
  files/etc/uci-defaults/zzza-doornet2-shunt-presets \
  files/etc/uci-defaults/zzzb-doornet2-network-apps

mkdir -p \
  files/etc/uci-defaults \
  files/lib/upgrade/keep.d

cat > files/etc/uci-defaults/zzzb-doornet2-network-apps <<'EOF'
#!/bin/sh

# This script is intentionally a FIRST-BOOT-ONLY default initializer.
# OpenWrt removes successful /etc/uci-defaults scripts after they run.
# It must never overwrite the user's settings on ordinary reboots.
#
# A persistent marker is preserved by sysupgrade.  Therefore a retained
# online upgrade will NOT re-apply the clean-install OFF defaults.
MARKER="/etc/doornet2-user-network-initialized"
UPGRADE_STATE="/etc/doornet2-upgrade-service-state"

if [ -e "$MARKER" ]; then
    # Online upgrade records AdGuard Home's enable/disable state because
    # its package primarily uses /etc/rc.d symlinks rather than a UCI
    # enabled flag.  Restore that state after the new image boots.
    if [ -f "$UPGRADE_STATE" ] && [ -x /etc/init.d/adguardhome ]; then
        if grep -qx 'adguardhome_enabled=1' "$UPGRADE_STATE"; then
            /etc/init.d/adguardhome enable >/dev/null 2>&1 || true
        else
            /etc/init.d/adguardhome disable >/dev/null 2>&1 || true
            /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
        fi
        rm -f "$UPGRADE_STATE"
    fi
    exit 0
fi

# PassWall / PassWall2: keep the normal init hooks installed so that
# once the user enables the plugin in LuCI, it can still auto-start on
# future reboots.  Only the package's UCI switch is set off initially.
if uci -q get passwall.@global[0] >/dev/null 2>&1; then
    uci -q set passwall.@global[0].enabled='0'
    uci -q set passwall.@global[0].socks_enabled='0'
    uci -q commit passwall
fi

if uci -q get passwall2.@global[0] >/dev/null 2>&1; then
    uci -q set passwall2.@global[0].enabled='0'
    uci -q set passwall2.@global[0].socks_enabled='0'
    uci -q commit passwall2
fi

# SmartDNS: installed but off by default.  Its init hook remains in
# place so enabling it later in LuCI persists across reboots.
if uci -q get smartdns.@smartdns[0] >/dev/null 2>&1; then
    uci -q set smartdns.@smartdns[0].enabled='0'
    uci -q commit smartdns
fi

# Stop the optional services on the clean first boot.
for svc in passwall passwall2 smartdns; do
    if [ -x "/etc/init.d/$svc" ]; then
        "/etc/init.d/$svc" stop >/dev/null 2>&1 || true
    fi
done

# AdGuard Home has no equivalent stock UCI enable flag in this package.
# Keep it installed but remove its boot symlink on the clean first boot.
# After the user finishes configuring AdGuard Home, enabling its service
# once (LuCI/iStore or /etc/init.d/adguardhome enable) makes that choice
# persist normally across later reboots.
if [ -x /etc/init.d/adguardhome ]; then
    /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
    /etc/init.d/adguardhome disable >/dev/null 2>&1 || true
fi

# dnsmasq-full is deliberately NOT disabled.  It is the router's base
# DHCP/DNS service.  A clean image uses its normal WAN resolv.conf
# upstreams.  As a first-boot safety net, explicitly remove any stale
# forced localhost DNS chain inherited from an old source template.
if uci -q get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
    uci -q delete dhcp.@dnsmasq[0].noresolv
    uci -q delete dhcp.@dnsmasq[0].server
    uci -q set dhcp.@dnsmasq[0].resolvfile='/tmp/resolv.conf.d/resolv.conf.auto'
    uci -q commit dhcp
fi

# Mark the clean-install initialization as completed.  This marker is
# explicitly retained during later sysupgrades so user settings are not
# reset to OFF after an online firmware update.
touch "$MARKER"

exit 0
EOF

chmod 755 files/etc/uci-defaults/zzzb-doornet2-network-apps
sh -n files/etc/uci-defaults/zzzb-doornet2-network-apps

cat > files/lib/upgrade/keep.d/doornet2-user-network-config <<'EOF'
# DoorNet2 user-managed network application settings.
# /etc/config is preserved by normal sysupgrade already; these explicit
# entries also cover non-UCI files used by the applications.
/etc/config/dhcp
/etc/config/passwall
/etc/config/passwall2
/etc/config/passwall_server
/etc/config/passwall2_server
/etc/config/smartdns
/etc/config/adguardhome
/etc/passwall/
/etc/passwall2/
/etc/smartdns/
/etc/adguardhome.yaml
/etc/doornet2-user-network-initialized
/etc/doornet2-upgrade-service-state
EOF

echo "===== CLEAN DEFAULT POLICY ====="
echo "PassWall:    installed, default OFF"
echo "PassWall2:   installed, default OFF"
echo "SmartDNS:    installed, default OFF"
echo "AdGuardHome: installed, default OFF"
echo "dnsmasq-full: installed, normal base service ON, no forced DNS chain"
echo "User settings are not rewritten on normal reboots."
