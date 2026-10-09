#!/usr/bin/env bash
# Migrated from V1.7 workflow step 47: Prepare artifact
set -e

mkdir -p \
  ./artifact/package \
  ./artifact/buildinfo \
  ./artifact/firmware \
  ./artifact/release


find ./bin/packages/ \
  -type f \
  -name "*.ipk" \
  -exec cp -f {} ./artifact/package/ \;


find ./bin/targets/ \
  -type f \
  \( \
    -name "*.buildinfo" \
    -o -name "*.manifest" \
    -o -name "*.config" \
  \) \
  -exec cp -f {} ./artifact/buildinfo/ \;


find ./bin/targets/ \
  -type f \
  \( \
    -name "*.img" \
    -o -name "*.img.gz" \
    -o -name "*.bin" \
    -o -name "*.itb" \
    -o -name "*.gz" \
  \) \
  ! -path "*/packages/*" \
  -exec cp -f {} ./artifact/firmware/ \;


SOURCE_FW="$(
  find ./bin/targets/rockchip/armv8 \
    -maxdepth 1 \
    -type f \
    -name '*embedfire_doornet2-ext4-sysupgrade.img.gz' \
    | head -n 1
)"


if [ -z "$SOURCE_FW" ]; then

    echo "ERROR: DoorNet2 firmware not found"
    exit 1

fi


cp -f \
  "$SOURCE_FW" \
  ./artifact/release/DoorNet2-ext4-sysupgrade.img.gz


cd ./artifact/release


SHA256="$(
  sha256sum \
    DoorNet2-ext4-sysupgrade.img.gz \
  | awk '{print $1}'
)"


echo \
  "${SHA256}  DoorNet2-ext4-sysupgrade.img.gz" \
  > sha256sums.txt


cat > version.json <<EOF
{
  "board": "embedfire,doornet2",
  "version": "${DOORNET2_VERSION}",
  "tag": "${DOORNET2_TAG}",
  "build_date": "${DOORNET2_BUILD_DATE}",
  "commit": "${GITHUB_SHA}",
  "repository": "${GITHUB_REPOSITORY}",
  "asset": "DoorNet2-ext4-sysupgrade.img.gz",
  "sha256": "${SHA256}",
  "boot_policy": "tf-first-emmc-fallback",
  "mmc_layout": "mmcblk0-tf-mmcblk1-emmc",
  "tf_controller": "fe320000.mmc",
  "emmc_controller": "fe330000.mmc",
  "extroot": false,
  "updater": "physical-target-guard-v2",
  "tf_capacity": "preserve-expanded-root-v1",
  "network_apps": "passwall-passwall2-smartdns-adguard-user-managed-shunt-v5",
  "ui": "quickstart-design-dark-v1",
  "runtime_monitor": "thermal-time-v2"
}
EOF


cat > release-notes.md <<EOF
# ${DOORNET2_VERSION}

R18 storage layout:

- U-Boot mmc1 = TF
- U-Boot mmc0 = eMMC
- Linux mmcblk0 = TF
- Linux mmcblk1 = eMMC
- TF controller = fe320000.mmc
- eMMC controller = fe330000.mmc
- TF physical type = SD
- eMMC physical type = MMC

Boot:

- TF inserted -> TF kernel + TF rootfs
- TF removed -> automatic eMMC fallback

Upgrade protection:

- Check MMC host aliases
- Check physical SD/MMC type
- Check controller path
- Check current root disk
- Check OpenWrt sysupgrade diskdev
- Reject upgrade if any result differs

TF capacity preservation:

- Firmware image remains 7 GiB for eMMC compatibility
- Expanded TF p2 partition table is preserved during sysupgrade
- ext4 is automatically grown back to the existing TF p2 size
- eMMC keeps the original Rockchip upgrade behaviour

Final interface:

- Design theme is the default LuCI shell
- QuickStart remains the iStoreOS-style home/workflow page
- Design dark mode is enabled by default
- Argon and Bootstrap remain installed as recovery themes
- CPU temperature + router date/time use a separate theme-independent badge
- Installed theme headers are patched on first boot as a safety net

Built-in shunt presets:

- PassWall and PassWall2 both include a user-facing "分流总节点" preset
- WeChatTencent is rule #1 in both PassWall and PassWall2 and is explicitly pinned to direct
- 42 built-in rules use the requested fixed order from WeChatTencent through Xbox
- Signing key policy is transitional: persistent secret is used when present, otherwise the build system may generate a temporary per-build key
- Original OpenWrt sysupgrade signature is verified before the R4 U-Boot patch; rebuilt image is re-signed and verified again
- Final image metadata is hard-checked for metadata_version 1.1 and embedfire,doornet2
- Existing release tags are immutable and cannot be overwritten
- Other service rules are preloaded but do not contain personal node IDs
- User node selections and edited rules are preserved across retained online upgrades
- No UU-specific rule, menu, runtime, or updater is included

Online-updatable network applications:

- PassWall proxy routing
- SmartDNS DNS acceleration
- PassWall2 proxy routing
- AdGuard Home
- Updates come from the DoorNet2 OPKG feed built by this workflow
- Kernel/kmod packages are never selected by the component updater

SHA256:

${SHA256}
EOF


ls -lah

cat version.json
