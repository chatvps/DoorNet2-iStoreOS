#!/usr/bin/env bash
# Migrated from V1.7 workflow step 38: Preflight package selection sanity checks
set -e

echo "===== PASSWALL / PASSWALL2 DEPENDENCY PREFLIGHT ====="

grep -q '^CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y$' .config

if grep -Eq '^CONFIG_PACKAGE_(geoview|sing-box|v2ray-plugin|shadowsocks-rust-sslocal|shadowsocks-rust-ssserver|shadowsocksr-libev-ssr-local|shadowsocksr-libev-ssr-redir|shadowsocksr-libev-ssr-server)=y$' .config; then
    echo "ERROR: an incompatible PassWall component was re-selected before compile."
    exit 1
fi

RUST_MK="feeds/packages/lang/rust/Makefile"
test -f "$RUST_MK"
grep -q -- '--set=llvm.download-ci-llvm=false' "$RUST_MK"

PW2_MK="feeds/passwall2_luci/luci-app-passwall2/Makefile"
test -f "$PW2_MK"
if grep -Eq '(^|[[:space:]])\+geoview([[:space:]]|$)' "$PW2_MK"; then
    echo "ERROR: PassWall2 +geoview dependency is active."
    exit 1
fi

echo "===== UU FINAL PREFLIGHT ====="
if grep -Eq '^CONFIG_PACKAGE_.*(uugamebooster|uuplugin).*=y$' .config; then
    echo "ERROR: UU package selected before compile."
    exit 1
fi

if grep -RniE 'uugamebooster|uuplugin|网易[[:space:]]*UU|NetEase[[:space:]]+UU' files 2>/dev/null; then
    echo "ERROR: UU runtime content exists in firmware overlay."
    exit 1
fi

if grep -RniE 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' files 2>/dev/null; then
    echo "ERROR: UU-specific domain exists in firmware overlay."
    exit 1
fi

echo "OK: dependency preflight passed."
