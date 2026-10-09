#!/usr/bin/env bash
# Migrated from V1.7 workflow step 37: Download packages
set -e

echo "===== CLEAN STALE BUILD OUTPUTS ====="
rm -rf ./artifact
rm -rf ./bin/targets/rockchip/armv8

make download -j16

find dl             -size -1024c             -exec rm -f {} \;
