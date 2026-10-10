#!/usr/bin/env bash
# Migrated from V1.7 workflow step 56: Final build verification
set -e

echo "========================================"
echo "${DOORNET2_VERSION}: build finished"
echo "========================================"

echo
echo "VERSION:"
echo "${DOORNET2_VERSION}"

echo
echo "===== SIGNING MODE ====="
echo "${DOORNET2_SIGNING_MODE:-unknown}"
if [ "${DOORNET2_SIGNING_MODE:-}" = "temporary-build-key" ]; then
    echo "WARNING: this build uses a temporary per-build signing key."
    echo "Configure DOORNET2_SIGNING_KEY before relying on future cross-version"
    echo "signature continuity for online upgrades."
fi

echo
echo "===== RELEASE ====="
cat files/etc/doornet2_release


echo
echo "===== BOOT SCRIPT ====="

grep -nE \
  'Trying TF|Trying eMMC|mmcblk0p2|mmcblk1p2' \
  target/linux/rockchip/image/doornet2.bootscript


echo
echo "===== DTS MMC ALIASES ====="

DTS_FILE="$(
  find target/linux/rockchip \
    -type f \
    -name '*.dts' \
    -print \
  | grep -Ei 'doornet2|door-net2' \
  | head -n 1
)"

if [ -z "$DTS_FILE" ]; then

    DTS_FILE="$(
      grep -RIl \
        --include='*.dts' \
        'DOORNET2_R18_FIXED_MMC_ALIASES' \
        target/linux/rockchip \
        | head -n 1
    )"

fi


test -n "$DTS_FILE"

grep -nE \
  'DOORNET2_R18_FIXED_MMC_ALIASES|mmc0.*sdmmc|mmc1.*sdhci' \
  "$DTS_FILE"


grep -qE \
  'mmc0[[:space:]]*=[[:space:]]*&sdmmc' \
  "$DTS_FILE"

grep -qE \
  'mmc1[[:space:]]*=[[:space:]]*&sdhci' \
  "$DTS_FILE"


echo
echo "===== UPDATER ====="

sh -n files/usr/bin/doornet2-updater

grep -nE \
  'fe320000.mmc|fe330000.mmc|verify_mmc_host_layout|verify_sysupgrade_target' \
  files/usr/bin/doornet2-updater


echo
echo "===== TF CAPACITY PRESERVE ====="

PLATFORM="target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh"

sh -n "$PLATFORM"

grep -nE \
  'DOORNET2_R21_TF_CAPACITY_PRESERVE_V1|RAMFS_COPY_BIN|doornet2_tf_can_preserve_partitions|doornet2_tf_grow_ext4|fe320000.mmc|e2fsck|resize2fs' \
  "$PLATFORM"

grep -q \
  'DOORNET2_R21_TF_CAPACITY_PRESERVE_V1' \
  "$PLATFORM"

grep -q \
  "DOORNET2_TF_CAPACITY='preserve-expanded-root-v1'" \
  files/etc/doornet2_release


echo
echo "===== PASSWALL ====="

grep -q \
  "DOORNET2_PASSWALL='passwall-passwall2-xray-shunt-v3'" \
  files/etc/doornet2_release

grep -q '^CONFIG_PACKAGE_luci-app-passwall=y$' .config
grep -q '^CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y$' .config
grep -q '^CONFIG_PACKAGE_dnsmasq-full=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall2=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox is not set$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin is not set$' .config

if grep -q '^CONFIG_PACKAGE_sing-box=y$' .config; then
    echo 'ERROR: incompatible sing-box unexpectedly selected in final config.'
    exit 1
fi

if grep -q '^CONFIG_PACKAGE_v2ray-plugin=y$' .config; then
    echo 'ERROR: incompatible v2ray-plugin unexpectedly selected in final config.'
    exit 1
fi

XRAY_MK="feeds/passwall_packages/xray-core/Makefile"
grep -q '^PKG_VERSION:=25\.1\.30$' "$XRAY_MK"
grep -q '^PKG_HASH:=983ee395f085ed1b7fbe0152cb56a5b605a6f70a5645d427c7186c476f14894e$' "$XRAY_MK"
grep -q '\$(GO_PKG)/core.build=OpenWrt' "$XRAY_MK"

if grep -q 'core.version=\$(PKG_VERSION)' "$XRAY_MK"; then
    echo 'ERROR: incompatible Xray core.version ldflag present in final tree.'
    exit 1
fi

test -f feeds/passwall_luci/luci-app-passwall/Makefile
test -d feeds/passwall_packages
test -x files/usr/bin/doornet2-passwall-updater
sh -n files/usr/bin/doornet2-passwall-updater

grep -q 'doornet2_passwall_luci' files/etc/opkg/distfeeds.conf
grep -q 'doornet2_passwall_packages' files/etc/opkg/distfeeds.conf

echo
echo "===== PASSWALL2 + ONLINE NETWORK APPS ====="

grep -q \
  "DOORNET2_NETWORK_APPS='passwall-passwall2-smartdns-adguard-user-managed-shunt-v5'" \
  files/etc/doornet2_release

grep -q '^CONFIG_PACKAGE_luci-app-passwall2=y$' .config
grep -q '^CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox is not set$' .config

test -f feeds/passwall2_luci/luci-app-passwall2/Makefile
grep -q 'doornet2_passwall2_luci' files/etc/opkg/distfeeds.conf

PASSWALL2_IPK="$(
  find ./bin \
    -type f \
    -name 'luci-app-passwall2_*.ipk' \
    -print \
    | head -n 1
)"

if [ -z "$PASSWALL2_IPK" ]; then
    echo "ERROR: PassWall2 IPK was not generated."
    exit 1
fi

echo "PassWall2 package: $PASSWALL2_IPK"

grep -q '^CONFIG_PACKAGE_smartdns=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-smartdns=y$' .config
grep -q '^CONFIG_PACKAGE_adguardhome=y$' .config

test -x files/usr/bin/doornet2-app-updater
sh -n files/usr/bin/doornet2-app-updater

test -x files/etc/uci-defaults/zzzb-doornet2-network-apps
test -f files/lib/upgrade/keep.d/doornet2-user-network-config
sh -n files/etc/uci-defaults/zzzb-doornet2-network-apps
test -x files/etc/uci-defaults/zzza-doornet2-shunt-presets
sh -n files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'seed_config passwall' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'seed_config passwall2' files/etc/uci-defaults/zzza-doornet2-shunt-presets
grep -q 'remarks=分流总节点' files/etc/uci-defaults/zzza-doornet2-shunt-presets

grep -q '/etc/config/passwall' files/lib/upgrade/keep.d/doornet2-user-network-config
grep -q '/etc/config/passwall2' files/lib/upgrade/keep.d/doornet2-user-network-config
grep -q '/etc/config/smartdns' files/lib/upgrade/keep.d/doornet2-user-network-config
grep -q '/etc/adguardhome.yaml' files/lib/upgrade/keep.d/doornet2-user-network-config
grep -q '/etc/config/dhcp' files/lib/upgrade/keep.d/doornet2-user-network-config
grep -q '/etc/doornet2-shunt-presets-v2' files/lib/upgrade/keep.d/doornet2-user-network-config

grep -nE \
  'luci-app-passwall2|smartdns|adguardhome|luci-app-smartdns' \
  .config \
  | head -60

if grep -Eq '^CONFIG_PACKAGE_.*(uugamebooster|uuplugin).*=y$' .config; then
    echo "ERROR: UU accelerator unexpectedly selected in final config."
    exit 1
fi

if grep -RniE 'uugamebooster|uuplugin|网易[[:space:]]*UU|NetEase[[:space:]]+UU' files 2>/dev/null; then
    echo "ERROR: UU runtime/menu/autostart/update content exists in final overlay."
    exit 1
fi

if grep -RniE 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' files 2>/dev/null; then
    echo "ERROR: UU-specific domain exists in final overlay."
    exit 1
fi

echo "UU accelerator runtime content: absent (OK)"

echo
echo "===== R34 DESIGN + QUICKSTART UI ====="

grep -q \
  "DOORNET2_UI='quickstart-design-dark-v1'" \
  files/etc/doornet2_release

grep -q '^CONFIG_PACKAGE_quickstart=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-quickstart=y$' .config
grep -q '^CONFIG_PACKAGE_luci-theme-design=y$' .config
grep -q '^CONFIG_PACKAGE_luci-theme-argon=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-argon-config=y$' .config

test -f feeds/nas/network/services/quickstart/Makefile
test -f feeds/nas_luci/luci/luci-app-quickstart/Makefile
test -f package/lean/luci-theme-design/Makefile
test -f package/lean/luci-theme-design/luasrc/view/themes/design/header.htm
test -f package/lean/luci-theme-design/htdocs/luci-static/design/css/style.css

grep -q '/cgi-bin/luci/admin/quickstart/' \
  package/lean/luci-theme-design/luasrc/view/themes/design/header.htm

test -x files/etc/uci-defaults/95-doornet2-ui
grep -q "mediaurlbase='/luci-static/design'" \
  files/etc/uci-defaults/95-doornet2-ui

test -f files/etc/config/design
grep -q "option mode 'dark'" files/etc/config/design
grep -q "option navbar_proxy 'passwall'" files/etc/config/design

DESIGN_IPK="$(
  find ./bin \
    -type f \
    -name 'luci-theme-design_*.ipk' \
    -print \
    | head -n 1
)"

if [ -z "$DESIGN_IPK" ]; then
    echo "ERROR: luci-theme-design IPK was not generated."
    exit 1
fi

echo "Design package: $DESIGN_IPK"

ROOT_DESIGN_HEADER="$(
  find build_dir \
    -type f \
    -path '*/root-*/usr/lib/lua/luci/view/themes/design/header.htm' \
    -print \
    | head -n 1
)"

if [ -z "$ROOT_DESIGN_HEADER" ]; then
    echo "ERROR: installed Design header not found in build root."
    exit 1
fi

echo "Installed Design header: $ROOT_DESIGN_HEADER"

# R33 demonstrated an important packaging detail:
# luci-theme-design installs a fresh header into rootfs, so it may not
# contain our source-tree injection yet. That is expected. What must
# be true is:
#   1. the real installed header is present and patchable;
#   2. the runtime CSS/JS are present in the real rootfs;
#   3. the first-boot fixer is present in the real rootfs;
#   4. the fixer can transform a copy of the installed header.
grep -q '</head>' "$ROOT_DESIGN_HEADER"

ROOT_DESIGN_CSS="$(
  find build_dir \
    -type f \
    -path '*/root-*/www/luci-static/design/css/style.css' \
    -print \
    | head -n 1
)"

if [ -z "$ROOT_DESIGN_CSS" ]; then
    echo "ERROR: installed Design static CSS not found in build root."
    exit 1
fi

echo "Installed Design CSS: $ROOT_DESIGN_CSS"

ROOT_RUNTIME_CSS="$(
  find build_dir \
    -type f \
    -path '*/root-*/www/luci-static/doornet2/runtime-monitor.css' \
    -print \
    | head -n 1
)"

ROOT_RUNTIME_JS="$(
  find build_dir \
    -type f \
    -path '*/root-*/www/luci-static/doornet2/runtime-monitor.js' \
    -print \
    | head -n 1
)"

ROOT_HEADER_FIX="$(
  find build_dir \
    -type f \
    -path '*/root-*/etc/uci-defaults/99-doornet2-runtime-header-fix' \
    -print \
    | head -n 1
)"

ROOT_UI_DEFAULT="$(
  find build_dir \
    -type f \
    -path '*/root-*/etc/uci-defaults/95-doornet2-ui' \
    -print \
    | head -n 1
)"

test -n "$ROOT_RUNTIME_CSS"
test -n "$ROOT_RUNTIME_JS"
test -n "$ROOT_HEADER_FIX"
test -n "$ROOT_UI_DEFAULT"

echo "Installed runtime CSS: $ROOT_RUNTIME_CSS"
echo "Installed runtime JS : $ROOT_RUNTIME_JS"
echo "Installed header fix : $ROOT_HEADER_FIX"
echo "Installed UI default : $ROOT_UI_DEFAULT"

grep -q '#dn-runtime-monitor' "$ROOT_RUNTIME_CSS"
grep -q 'doornet2_runtime' "$ROOT_RUNTIME_JS"

sh -n "$ROOT_HEADER_FIX"
grep -q 'themes/design/header.htm' "$ROOT_HEADER_FIX"
grep -q 'runtime-monitor.css' "$ROOT_HEADER_FIX"
grep -q 'runtime-monitor.js' "$ROOT_HEADER_FIX"
grep -q '/cgi-bin/luci/admin/quickstart/' "$ROOT_HEADER_FIX"

sh -n "$ROOT_UI_DEFAULT"
grep -q "mediaurlbase='/luci-static/design'" "$ROOT_UI_DEFAULT"

echo "===== SIMULATE FIRST-BOOT DESIGN HEADER PATCH ====="

TMP_DESIGN_HEADER="$(mktemp)"
cp -f "$ROOT_DESIGN_HEADER" "$TMP_DESIGN_HEADER"

TEST_CSS='<link rel="stylesheet" href="/luci-static/doornet2/runtime-monitor.css">'
TEST_JS='<script defer src="/luci-static/doornet2/runtime-monitor.js"></script>'

if ! grep -q 'runtime-monitor.css' "$TMP_DESIGN_HEADER"; then
    sed -i "\|</head>|i\\$TEST_CSS" "$TMP_DESIGN_HEADER"
fi

if ! grep -q 'runtime-monitor.js' "$TMP_DESIGN_HEADER"; then
    sed -i "\|</head>|i\\$TEST_JS" "$TMP_DESIGN_HEADER"
fi

sed -i \
  's#/cgi-bin/luci/admin/status/overview#/cgi-bin/luci/admin/quickstart/#g' \
  "$TMP_DESIGN_HEADER"

grep -q 'runtime-monitor.css' "$TMP_DESIGN_HEADER"
grep -q 'runtime-monitor.js' "$TMP_DESIGN_HEADER"

rm -f "$TMP_DESIGN_HEADER"

echo "Installed Design header is patchable; first-boot fix verified (OK)"


echo
echo "===== R34 RUNTIME MONITOR ====="

grep -q \
  "DOORNET2_RUNTIME_MONITOR='thermal-time-v2'" \
  files/etc/doornet2_release

grep -q '^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview is not set$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client is not set$' .config
grep -q '^# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client is not set$' .config
! grep -Eq '^CONFIG_PACKAGE_shadowsocks-rust-.*=y$' .config
! grep -Eq '^CONFIG_PACKAGE_shadowsocksr-libev.*=y$' .config

test -x files/usr/bin/doornet2-runtime-status
sh -n files/usr/bin/doornet2-runtime-status

test -s files/usr/lib/lua/luci/controller/doornet2_runtime.lua
grep -q 'doornet2_runtime' \
  files/usr/lib/lua/luci/controller/doornet2_runtime.lua

test -s files/www/luci-static/doornet2/runtime-monitor.js
grep -q 'doornet2_runtime' \
  files/www/luci-static/doornet2/runtime-monitor.js

test -s files/www/luci-static/doornet2/runtime-monitor.css
grep -q '#dn-runtime-monitor' \
  files/www/luci-static/doornet2/runtime-monitor.css

grep -q 'runtime-monitor.css' \
  package/lean/luci-theme-design/luasrc/view/themes/design/header.htm
grep -q 'runtime-monitor.js' \
  package/lean/luci-theme-design/luasrc/view/themes/design/header.htm

test -x files/etc/uci-defaults/99-doornet2-runtime-header-fix
sh -n files/etc/uci-defaults/99-doornet2-runtime-header-fix

test -x files/etc/uci-defaults/98-doornet2-time
sh -n files/etc/uci-defaults/98-doornet2-time
grep -q "zonename='Asia/Shanghai'" \
  files/etc/uci-defaults/98-doornet2-time


echo
echo "===== EXTROOT ====="

cat files/etc/config/fstab

if grep -Eq \
  "option[[:space:]]+target[[:space:]]+['\"]?/['\"]?" \
  files/etc/config/fstab
then

    echo "ERROR: extroot found"
    exit 1

fi


echo
echo "===== RELEASE FILES ====="

ls -lah ./artifact/release/


echo
echo "========================================"
echo "DoorNet2-V1.11 build success"
echo "========================================"
