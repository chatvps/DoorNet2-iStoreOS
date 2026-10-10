#!/usr/bin/env bash
# Migrated from V1.7 workflow step 35: Generate configuration file
set -e

make defconfig

echo "===== TARGET ====="
grep '^CONFIG_TARGET_.*=y' .config || true

if grep -Eq '^CONFIG_TARGET_x86(_64)?=y' .config; then
    echo "ERROR: x86 target detected. This build must be DoorNet2 RK3399."
    exit 1
fi

grep -q '^CONFIG_TARGET_rockchip=y$' .config
grep -q '^CONFIG_TARGET_rockchip_armv8=y$' .config
grep -q '^CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_embedfire_doornet2=y$' .config

grep -q '^CONFIG_SIGNED_PACKAGES=y$' .config || {
    echo "ERROR: CONFIG_SIGNED_PACKAGES must stay enabled for persistent key trust."
    exit 1
}

if grep -RqsE '^[[:space:]]*config[[:space:]]+SIGN_FIRMWARE[[:space:]]*$' config; then
    grep -q '^CONFIG_SIGN_FIRMWARE=y$' .config || {
        echo "ERROR: CONFIG_SIGN_FIRMWARE exists in this source tree but is not enabled."
        exit 1
    }
else
    echo "INFO: legacy source tree has no CONFIG_SIGN_FIRMWARE symbol."
    echo "      Firmware signing will use the historical build-key-controlled path."
fi

if grep -q '^CONFIG_BUILDBOT=y$' .config; then
    echo "ERROR: CONFIG_BUILDBOT=y would suppress installation of the local signing key."
    exit 1
fi

grep -Rqs 'usign[[:space:]].*-S' include || {
    echo "ERROR: source tree does not expose a firmware usign signing recipe."
    exit 1
}

grep -Rqs 'fwtool[[:space:]].*-S' include || {
    echo "ERROR: source tree does not expose fwtool signature attachment."
    exit 1
}

for sym in CONFIG_PACKAGE_usign CONFIG_PACKAGE_ucert; do
    grep -q "^${sym}=y$" .config || {
        echo "ERROR: runtime signature verifier missing: ${sym}=y"
        exit 1
    }
done

if [ "${DOORNET2_SIGNING_MODE:-}" = "persistent-key" ]; then
    test -s key-build
    test -s key-build.pub
else
    test ! -e key-build || {
        echo "ERROR: temporary-key mode unexpectedly has a pre-build key-build file."
        exit 1
    }
    test ! -e key-build.pub || {
        echo "ERROR: temporary-key mode unexpectedly has a pre-build key-build.pub file."
        exit 1
    }
fi

test ! -e key-build.ucert || {
    echo "ERROR: key-build.ucert exists before build and may be stale."
    exit 1
}

echo
echo "===== VERSION ====="
cat files/etc/doornet2_release

echo
echo "===== UPDATER ====="
sh -n files/usr/bin/doornet2-updater
grep -nE             'fe320000|fe330000|verify_mmc_host_layout|verify_sysupgrade_target'             files/usr/bin/doornet2-updater

echo
echo "===== PASSWALL / PASSWALL2 / XRAY ====="
for sym in             CONFIG_PACKAGE_luci-app-passwall             CONFIG_PACKAGE_luci-i18n-passwall-zh-cn             CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray             CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy             CONFIG_PACKAGE_luci-app-passwall2             CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn             CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray             CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy             CONFIG_PACKAGE_dnsmasq-full             CONFIG_PACKAGE_iptables             CONFIG_PACKAGE_ip6tables             CONFIG_PACKAGE_kmod-ip6tables; do
    grep -q "^${sym}=y$" .config || {
        echo "ERROR: required symbol missing: ${sym}=y"
        exit 1
    }
done

if grep -Eq '^CONFIG_PACKAGE_luci-app-passwall2?_Nftables_Transparent_Proxy=y$|^CONFIG_PACKAGE_firewall4=y$' .config; then
    echo "ERROR: nftables/firewall4 was unexpectedly selected on the proven R4 firewall3 base."
    grep -E 'passwall2?_Nftables_Transparent_Proxy|CONFIG_PACKAGE_firewall4' .config || true
    exit 1
fi

# These components caused the prior build failures or require a newer Go.
if grep -Eq '^CONFIG_PACKAGE_(geoview|sing-box|v2ray-plugin|shadowsocks-rust|shadowsocks-rust-sslocal|shadowsocks-rust-ssserver|shadowsocksr-libev|shadowsocksr-libev-ssr-local|shadowsocksr-libev-ssr-redir|shadowsocksr-libev-ssr-server)=y$' .config; then
    echo "ERROR: incompatible proxy component was re-selected."
    grep -E '^CONFIG_PACKAGE_(geoview|sing-box|v2ray-plugin|shadowsocks-rust|shadowsocks-rust-sslocal|shadowsocks-rust-ssserver|shadowsocksr-libev|shadowsocksr-libev-ssr-local|shadowsocksr-libev-ssr-redir|shadowsocksr-libev-ssr-server)=y$' .config || true
    exit 1
fi

if grep -Eq '^CONFIG_PACKAGE_luci-app-passwall2?_INCLUDE_(V2ray_Plugin|Shadowsocks_Rust_Client|Shadowsocks_Rust_Server|ShadowsocksR_Libev_Client|ShadowsocksR_Libev_Server)=y$' .config; then
    echo "ERROR: PassWall/PassWall2 selector re-enabled an incompatible component."
    exit 1
fi

grep -q '^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview is not set$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox is not set$' .config

XRAY_MK="feeds/passwall_packages/xray-core/Makefile"
grep -q '^PKG_VERSION:=25\.1\.30$' "$XRAY_MK"
grep -q '^PKG_HASH:=983ee395f085ed1b7fbe0152cb56a5b605a6f70a5645d427c7186c476f14894e$' "$XRAY_MK"
grep -q '\$(GO_PKG)/core.build=OpenWrt' "$XRAY_MK"
if grep -q 'core.version=\$(PKG_VERSION)' "$XRAY_MK"; then
    echo "ERROR: incompatible Xray core.version ldflag returned."
    exit 1
fi

PW2_MK="feeds/passwall2_luci/luci-app-passwall2/Makefile"
test -f "$PW2_MK"
if grep -Eq '(^|[[:space:]])\+geoview([[:space:]]|$)' "$PW2_MK"; then
    echo "ERROR: PassWall2 +geoview hard dependency returned."
    exit 1
fi

echo
echo "===== ISTORE / DNS / UI ====="
for sym in             CONFIG_PACKAGE_luci-app-store             CONFIG_PACKAGE_smartdns             CONFIG_PACKAGE_luci-app-smartdns             CONFIG_PACKAGE_adguardhome             CONFIG_PACKAGE_quickstart             CONFIG_PACKAGE_luci-app-quickstart             CONFIG_PACKAGE_luci-theme-design             CONFIG_PACKAGE_luci-theme-argon             CONFIG_PACKAGE_luci-app-argon-config; do
    grep -q "^${sym}=y$" .config || {
        echo "ERROR: required final feature missing: ${sym}=y"
        exit 1
    }
done

echo
echo "===== UU ABSENCE CHECK ====="
if grep -Eq '^CONFIG_PACKAGE_.*(uugamebooster|uuplugin).*=y$' .config; then
    echo "ERROR: UU accelerator component is selected."
    grep -Ei 'uugamebooster|uuplugin' .config || true
    exit 1
fi

if grep -RniE 'uugamebooster|uuplugin|网易[[:space:]]*UU|NetEase[[:space:]]+UU' files 2>/dev/null; then
    echo "ERROR: UU runtime/menu/autostart/update content exists under files/."
    exit 1
fi

if grep -RniE 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' files 2>/dev/null; then
    echo "ERROR: legacy UU-specific domain exists under files/."
    exit 1
fi

test -x files/usr/bin/doornet2-passwall-updater
test -x files/usr/bin/doornet2-app-updater
test -x files/etc/uci-defaults/zzzb-doornet2-network-apps
test -f files/lib/upgrade/keep.d/doornet2-user-network-config
sh -n files/usr/bin/doornet2-app-updater
sh -n files/etc/uci-defaults/zzzb-doornet2-network-apps
test -x files/etc/uci-defaults/zzza-doornet2-shunt-presets
sh -n files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'seed_config passwall' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'seed_config passwall2' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'remarks=分流总节点' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'DN_WeChatTencent' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'DN_WeChatTencent:_direct' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'DN_GoogleWork' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'DN_Xbox' files/etc/uci-defaults/zzza-doornet2-shunt-presets
if grep -Ei 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' files/etc/uci-defaults/zzza-doornet2-shunt-presets; then
    echo "ERROR: UU-specific domain leaked into shunt presets."
    exit 1
fi

if [ -f files/etc/config/dhcp ]; then
    if grep -q '127\.0\.0\.1#3053' files/etc/config/dhcp || \
       grep -Eq "option[[:space:]]+noresolv[[:space:]]+['\"]?1" files/etc/config/dhcp; then
        echo "ERROR: old forced dnsmasq -> AdGuard chain is still baked in"
        cat files/etc/config/dhcp
        exit 1
    fi
fi

if find files -type f \
    \( -name 'doornet2-dns-chain' -o -name 'passwall-delay' -o -name 'passwall2-delay' \) \
    -print 2>/dev/null | grep -q .; then
    echo "ERROR: old automatic DNS/proxy rewrite scripts are still present"
    find files -type f \
      \( -name 'doornet2-dns-chain' -o -name 'passwall-delay' -o -name 'passwall2-delay' \) \
      -print
    exit 1
fi

echo "OK: DoorNet2 final configuration preflight passed."
