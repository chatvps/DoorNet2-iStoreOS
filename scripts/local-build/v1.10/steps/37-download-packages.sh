#!/usr/bin/env bash
# Migrated from V1.7 workflow step 37: Download packages
set -e

echo "===== CLEAN STALE BUILD OUTPUTS ====="
rm -rf ./artifact
rm -rf ./bin/targets/rockchip/armv8

# Remove only suspicious tiny top-level download files.
# Never recurse into structured caches such as dl/go-mod-cache.
find dl \
  -maxdepth 1 \
  -type f \
  -size -1024c \
  -print \
  -delete

make download -j16
