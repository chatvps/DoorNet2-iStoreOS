#!/usr/bin/env bash
# Migrated from V1.7 workflow step 44: Audit generated rootfs before publishing
set -e

# On this R4/OpenWrt tree the target emits a generic target rootfs tarball
# (openwrt-rockchip-armv8-rootfs.tar.gz), while the sysupgrade images are
# device-specific. Prefer a device-specific tarball if one ever exists,
# otherwise audit the generic rockchip/armv8 rootfs actually used to build
# the DoorNet2 image.
ROOTFS_TAR="$(
  find ./bin/targets/rockchip/armv8 \
    -maxdepth 1 -type f \
    \( -name '*embedfire_doornet2-rootfs.tar.gz' \
       -o -name 'openwrt-rockchip-armv8-rootfs.tar.gz' \
       -o -name '*-rootfs.tar.gz' \) \
    | sort \
    | head -n 1
)"

if [ -z "$ROOTFS_TAR" ]; then
    echo "ERROR: generated rockchip/armv8 rootfs tarball not found."
    echo "Files produced in target directory:"
    find ./bin/targets/rockchip/armv8 -maxdepth 1 -type f -printf '%f\n' | sort
    exit 1
fi

echo "Auditing rootfs tarball: $ROOTFS_TAR"

AUDIT_DIR="$(mktemp -d)"
trap 'rm -rf "$AUDIT_DIR"' EXIT
tar -xzf "$ROOTFS_TAR" -C "$AUDIT_DIR"

echo "===== R4 HARDWARE / KERNEL BASELINE CHECK ====="
cat "$AUDIT_DIR/etc/openwrt_release"
grep -q "DISTRIB_TARGET='rockchip/armv8'" "$AUDIT_DIR/etc/openwrt_release" || {
    echo "ERROR: generated firmware target is not rockchip/armv8."
    exit 1
}
grep -q "DISTRIB_ARCH='aarch64_generic'" "$AUDIT_DIR/etc/openwrt_release" || {
    echo "ERROR: generated firmware architecture is not aarch64_generic."
    exit 1
}
grep -q '^Package: kernel$' "$AUDIT_DIR/usr/lib/opkg/status"
awk 'BEGIN{p=0} /^Package: kernel$/{p=1} p && /^Version: /{print; exit}' \
  "$AUDIT_DIR/usr/lib/opkg/status" | grep -q 'Version: 6\.6\.66-1-' || {
    echo "ERROR: generated kernel is not the required DoorNet2 6.6.66 line."
    awk 'BEGIN{p=0} /^Package: kernel$/{p=1} p && /^Version: /{print; exit}' \
      "$AUDIT_DIR/usr/lib/opkg/status"
    exit 1
}
grep -q "DOORNET2_SOURCE_BASELINE='${DOORNET2_SOURCE_BASELINE}'" \
  "$AUDIT_DIR/etc/doornet2_release"
grep -q "DOORNET2_BASE_CONFIG_SHA256='${DOORNET2_BASE_CONFIG_SHA256}'" \
  "$AUDIT_DIR/etc/doornet2_release"
grep -q "DOORNET2_R4_REFERENCE='9d1be44f0c1eaf3100ba122a966ff86b66354792'" \
  "$AUDIT_DIR/etc/doornet2_release"
grep -q "DOORNET2_BOOT_MODE='tf-first-emmc-fallback'" \
  "$AUDIT_DIR/etc/doornet2_release"

echo "===== ROOTFS PACKAGE CHECK ====="
for pkg in \
  luci-app-passwall \
  luci-app-passwall2 \
  xray-core \
  smartdns \
  luci-app-smartdns \
  adguardhome \
  luci-app-store \
  dnsmasq-full \
  usign \
  ucert; do
    grep -q "^Package: ${pkg}$" "$AUDIT_DIR/usr/lib/opkg/status" || {
        echo "ERROR: required package missing from rootfs: $pkg"
        exit 1
    }
done

echo "===== ROOTFS DEFAULT DNS CHECK ====="
if grep -q '127\.0\.0\.1#3053' "$AUDIT_DIR/etc/config/dhcp" || \
   grep -Eq "option[[:space:]]+noresolv[[:space:]]+['\"]?1" "$AUDIT_DIR/etc/config/dhcp"; then
    echo "ERROR: generated rootfs still contains the old forced dnsmasq -> AdGuard chain."
    cat "$AUDIT_DIR/etc/config/dhcp"
    exit 1
fi

grep -q "option 'enabled' '0'" "$AUDIT_DIR/etc/config/smartdns" || {
    echo "ERROR: SmartDNS is not OFF by default in generated rootfs."
    exit 1
}

test -x "$AUDIT_DIR/etc/uci-defaults/zzzb-doornet2-network-apps"
test -f "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"
grep -q '/etc/config/passwall' "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"
grep -q '/etc/config/passwall2' "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"
grep -q '/etc/config/smartdns' "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"
grep -q '/etc/adguardhome.yaml' "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"
grep -q '/etc/config/dhcp' "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"
grep -q '/etc/doornet2-shunt-presets-v2' "$AUDIT_DIR/lib/upgrade/keep.d/doornet2-user-network-config"

echo "===== ROOTFS SIGNING KEY CHECK ====="
HOST_USIGN="${GITHUB_WORKSPACE}/staging_dir/host/bin/usign"
test -x "$HOST_USIGN"
test -s "${GITHUB_WORKSPACE}/key-build.pub"

SIGNING_FINGERPRINT="$("$HOST_USIGN" -F -p "${GITHUB_WORKSPACE}/key-build.pub")"
test -n "$SIGNING_FINGERPRINT"

ROOTFS_KEY="$AUDIT_DIR/etc/opkg/keys/$SIGNING_FINGERPRINT"
test -s "$ROOTFS_KEY" || {
    echo "ERROR: DoorNet2 build signing public key is missing from rootfs."
    echo "Expected: $ROOTFS_KEY"
    exit 1
}

cmp -s "${GITHUB_WORKSPACE}/key-build.pub" "$ROOTFS_KEY" || {
    echo "ERROR: rootfs firmware trust key differs from this build signing key."
    exit 1
}

echo "Build signing fingerprint: $SIGNING_FINGERPRINT"

echo "===== ROOTFS SHUNT PRESET CHECK ====="
SHUNT_PRESET="$AUDIT_DIR/etc/uci-defaults/zzza-doornet2-shunt-presets"
test -x "$SHUNT_PRESET"
sh -n "$SHUNT_PRESET"
grep -q 'seed_config passwall' "$SHUNT_PRESET"
grep -q 'seed_config passwall2' "$SHUNT_PRESET"
grep -q 'remarks=分流总节点' "$SHUNT_PRESET"
grep -q 'DN_WeChatTencent' "$SHUNT_PRESET"
grep -q 'DN_OpenAI' "$SHUNT_PRESET"
grep -q 'DN_Netflix' "$SHUNT_PRESET"
grep -q 'qpic.cn' "$SHUNT_PRESET"
grep -q 'gtimg.com' "$SHUNT_PRESET"
grep -q 'DN_WeChatTencent:_direct' "$SHUNT_PRESET"

python3 - "$SHUNT_PRESET" <<'PY_ROOTFS_SHUNT'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

expected = [
    "DN_WeChatTencent",
    "DN_ChatGPT_Login",
    "DN_OpenAI",
    "DN_GitHub",
    "DN_GoogleWork",
    "DN_GoogleAI",
    "DN_YouTube",
    "DN_Netflix",
    "DN_Disney",
    "DN_MaxHBO",
    "DN_PrimeVideo",
    "DN_Twitter",
    "DN_Telegram",
    "DN_Google",
    "DN_TikTok",
    "DN_PlayStation",
    "DN_Nintendo",
    "DN_Instagram",
    "DN_Signal",
    "DN_Spotify",
    "DN_Slack",
    "DN_DirectGame",
    "DN_ProxyGame",
    "DN_AIGC",
    "DN_Streaming",
    "DN_Proxy",
    "DN_Direct",
    "DN_LINE",
    "DN_WhatsApp",
    "DN_Discord",
    "DN_Facebook",
    "DN_Reddit",
    "DN_Claude",
    "DN_Perplexity",
    "DN_Copilot",
    "DN_Grok",
    "DN_Apple",
    "DN_Microsoft",
    "DN_Zoom",
    "DN_Notion",
    "DN_Dropbox",
    "DN_Xbox",
]

actual = re.findall(
    r'add_rule "\$cfg" (DN_[A-Za-z0-9_]+) ',
    text,
)

if actual != expected:
    print("ERROR: generated rootfs shunt rule order mismatch.")
    print("Expected:", expected)
    print("Actual:  ", actual)
    raise SystemExit(1)

if len(actual) != 42 or len(set(actual)) != 42:
    raise SystemExit(
        "ERROR: generated rootfs must contain exactly 42 unique shunt rules."
    )

print("OK: generated rootfs contains the exact 42-rule policy.")
PY_ROOTFS_SHUNT

if grep -Ei 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' "$SHUNT_PRESET"; then
    echo "ERROR: UU-specific domain exists in generated shunt preset."
    exit 1
fi

echo "===== ROOTFS ONLINE-UPGRADE CHECK ====="
grep -q 'REPO="chatvps/DoorNet2-iStoreOS"' "$AUDIT_DIR/usr/bin/doornet2-updater"
grep -q 'keep_config.*true' "$AUDIT_DIR/usr/bin/doornet2-updater"
if grep -Eq '/sbin/sysupgrade[[:space:]\\]*-n|sysupgrade[[:space:]]+-n' "$AUDIT_DIR/usr/bin/doornet2-updater"; then
    echo "ERROR: updater contains sysupgrade -n and would discard settings."
    exit 1
fi

echo "===== ROOTFS REPOSITORY CHECK ====="
if grep -Rni 'bwgone/DoorNet2-iStoreOS' \
    "$AUDIT_DIR/etc" "$AUDIT_DIR/usr" 2>/dev/null; then
    echo "ERROR: stale bwgone repository URL is baked into generated rootfs."
    exit 1
fi

grep -q "DOORNET2_GITHUB_REPOSITORY='chatvps/DoorNet2-iStoreOS'" \
  "$AUDIT_DIR/etc/doornet2_release"

echo "===== ROOTFS UU ABSENCE CHECK ====="
if find "$AUDIT_DIR" \
    \( -iname '*uugamebooster*' -o -iname '*uuplugin*' -o -iname 'doornet2-uu' -o -iname 'uu-delay' \) \
    -print | grep -q .; then
    echo "ERROR: UU runtime file exists in generated rootfs."
    exit 1
fi

if grep -RniE 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' \
    "$AUDIT_DIR/etc" "$AUDIT_DIR/usr" 2>/dev/null; then
    echo "ERROR: UU-specific domain exists in generated rootfs."
    exit 1
fi

echo "OK: generated DoorNet2 rootfs audit passed."
