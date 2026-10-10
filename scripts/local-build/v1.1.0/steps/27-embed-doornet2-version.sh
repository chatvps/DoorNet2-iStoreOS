#!/usr/bin/env bash
# Migrated from V1.7 workflow step 27: Embed DoorNet2 version
set -e

mkdir -p files/etc

cat > files/etc/doornet2_release <<EOF
DOORNET2_VERSION='${DOORNET2_VERSION}'
DOORNET2_TAG='${DOORNET2_TAG}'
DOORNET2_BUILD_DATE='${DOORNET2_BUILD_DATE}'
DOORNET2_GIT_COMMIT='${GITHUB_SHA}'
DOORNET2_GITHUB_REPOSITORY='${GITHUB_REPOSITORY}'
DOORNET2_SOURCE_REPOSITORY='${DOORNET2_SOURCE_REPO}'
DOORNET2_SOURCE_BASELINE='${DOORNET2_SOURCE_BASELINE}'
DOORNET2_SOURCE_MODE='${DOORNET2_SOURCE_MODE}'
DOORNET2_BOOTLOADER='r4-9d1be44-exact-uboot-region'
DOORNET2_BASE_CONFIG_SHA256='${DOORNET2_BASE_CONFIG_SHA256}'
DOORNET2_R4_REFERENCE='${DOORNET2_R4_REFERENCE}'
DOORNET2_BOARD='embedfire,doornet2'
DOORNET2_BOOT_MODE='tf-first-emmc-fallback'
DOORNET2_STORAGE_FIX='no-extroot'
DOORNET2_MMC_LAYOUT='mmcblk0-tf-mmcblk1-emmc'
DOORNET2_UPDATER='physical-target-guard-v2'
DOORNET2_TF_CAPACITY='preserve-expanded-root-v1'
DOORNET2_UI='quickstart-design-dark-v1'
DOORNET2_PASSWALL='passwall-passwall2-xray-shunt-v3'
DOORNET2_NETWORK_APPS='passwall-passwall2-smartdns-adguard-user-managed-shunt-v5'
DOORNET2_RUNTIME_MONITOR='thermal-time-v2'
EOF

cat files/etc/doornet2_release
