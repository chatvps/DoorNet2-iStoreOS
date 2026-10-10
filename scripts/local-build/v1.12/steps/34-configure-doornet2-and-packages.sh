#!/usr/bin/env bash
# Migrated from V1.7 workflow step 34: Configure DoorNet2 and packages
set -e

# Match the proven R4 workflow exactly at config-generation time:
# there must be NO .config yet.  This `cat >>` creates it from scratch.
test -f /tmp/doornet2-proven-empty-config
test ! -e .config || {
    echo "ERROR: .config appeared before the proven package-selection step."
    echo "Refusing to mix another base config into the R4 build path."
    exit 1
}

cat >> .config <<'EOF'

CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_embedfire_doornet2=y

CONFIG_TARGET_KERNEL_PARTSIZE=64
CONFIG_TARGET_ROOTFS_PARTSIZE=7168

CONFIG_TARGET_ROOTFS_TARGZ=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y

# Stable cross-version package-signing/trust policy.
CONFIG_SIGNED_PACKAGES=y

CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-compat=y

# Shared DNS/proxy base
# CONFIG_PACKAGE_dnsmasq is not set
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_ip6tables=y
CONFIG_PACKAGE_kmod-ip6tables=y
# CONFIG_PACKAGE_firewall4 is not set

# PassWall: Xray only for the Go 1.23-compatible DoorNet2 tree.
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-i18n-passwall-zh-cn=y
CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy is not set
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Geoview is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client is not set
# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Server is not set
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs=y

# PassWall2: select Xray explicitly instead of the aarch64 default
# "All" core, which would pull current Sing-box and a newer Go toolchain.
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y
CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray=y
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox is not set
# CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All is not set
CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_V2ray_Plugin is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Client is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Shadowsocks_Rust_Server is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_ShadowsocksR_Libev_Client is not set
# CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_ShadowsocksR_Libev_Server is not set
CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Simple_Obfs=y

# Known incompatible packages are disabled at package level as well.
# CONFIG_PACKAGE_geoview is not set
# CONFIG_PACKAGE_sing-box is not set
# CONFIG_PACKAGE_v2ray-plugin is not set
# CONFIG_PACKAGE_shadowsocks-rust is not set
# CONFIG_PACKAGE_shadowsocks-rust-sslocal is not set
# CONFIG_PACKAGE_shadowsocks-rust-ssserver is not set
# CONFIG_PACKAGE_shadowsocksr-libev is not set
# CONFIG_PACKAGE_shadowsocksr-libev-ssr-local is not set
# CONFIG_PACKAGE_shadowsocksr-libev-ssr-redir is not set
# CONFIG_PACKAGE_shadowsocksr-libev-ssr-server is not set

# SmartDNS + AdGuard Home.  First-boot script leaves both disabled.
CONFIG_PACKAGE_smartdns=y
CONFIG_PACKAGE_luci-app-smartdns=y
CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y
CONFIG_PACKAGE_adguardhome=y

# UU accelerator is intentionally absent from the final firmware.
# CONFIG_PACKAGE_luci-app-uugamebooster is not set
# CONFIG_PACKAGE_uugamebooster is not set
# CONFIG_PACKAGE_luci-app-uuplugin is not set
# CONFIG_PACKAGE_uuplugin is not set

# iStoreOS-style QuickStart dashboard
CONFIG_PACKAGE_quickstart=y
CONFIG_PACKAGE_luci-app-quickstart=y
CONFIG_PACKAGE_luci-i18n-quickstart-zh-cn=y

# Design is default. Argon and Bootstrap remain recovery themes.
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-theme-design=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y

CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_jsonfilter=y

# Runtime firmware-signature verification.  usign is also selected by
# SIGNED_PACKAGES, but keep both explicit for upgrade safety.
CONFIG_PACKAGE_usign=y
CONFIG_PACKAGE_ucert=y

CONFIG_PACKAGE_lsblk=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_sfdisk=y
CONFIG_PACKAGE_blkid=y
CONFIG_PACKAGE_blockdev=y
CONFIG_PACKAGE_partx-utils=y
CONFIG_PACKAGE_mount-utils=y

CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_resize2fs=y
CONFIG_PACKAGE_tune2fs=y

CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-fs-ext4=y

EOF

# Newer OpenWrt trees gate image signing behind CONFIG_SIGN_FIRMWARE.
# Older LEDE/OpenWrt trees sign whenever BUILD_KEY material exists and
# do not define this Kconfig symbol.  Support both without a false fail.
if grep -RqsE '^[[:space:]]*config[[:space:]]+SIGN_FIRMWARE[[:space:]]*$' config; then
    echo 'CONFIG_SIGN_FIRMWARE=y' >> .config
    echo "Firmware signing mode: CONFIG_SIGN_FIRMWARE=y"
else
    echo "Firmware signing mode: legacy build-key-controlled signing"
fi
