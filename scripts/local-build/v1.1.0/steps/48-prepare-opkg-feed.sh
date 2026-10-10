#!/usr/bin/env bash
# Migrated from V1.7 workflow step 48: Prepare OPKG feed
set -e

rm -rf ./artifact/opkg-feed

mkdir -p \
  ./artifact/opkg-feed/packages \
  ./artifact/opkg-feed/targets/rockchip/armv8

cp -a \
  ./bin/packages/. \
  ./artifact/opkg-feed/packages/


if [ -d "./bin/targets/rockchip/armv8/packages" ]; then

    cp -a \
      ./bin/targets/rockchip/armv8/packages \
      ./artifact/opkg-feed/targets/rockchip/armv8/

else

    echo "ERROR: target package directory missing"
    exit 1

fi


cat > ./artifact/opkg-feed/README.md <<EOF
# DoorNet2 OPKG Feed

Version:
${DOORNET2_VERSION}

Target:
rockchip/armv8

Architecture:
aarch64_generic
EOF


COUNT="$(
  find ./artifact/opkg-feed \
    -type f \
    -name "Packages.gz" \
  | wc -l
)"


if [ "$COUNT" -lt 2 ]; then

    echo "ERROR: OPKG indexes missing"
    exit 1

fi
