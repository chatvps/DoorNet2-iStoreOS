#!/usr/bin/env bash
# Migrated from V1.7 workflow step 12: Patch PassWall2 geoview hard dependency
set -e

PW2_MK="feeds/passwall2_luci/luci-app-passwall2/Makefile"
test -f "$PW2_MK"

echo "===== BEFORE PATCH ====="
grep -n 'geoview' "$PW2_MK" || true

# PassWall2 currently hard-depends on geoview.  DoorNet2's legacy
# Go toolchain cannot build the current geoview release, while the
# PassWall2 core itself can run without the optional Geo View page.
sed -i -E             's/(^|[[:space:]])\+geoview([[:space:]]|$)/\1\2/g'             "$PW2_MK"

if grep -Eq '(^|[[:space:]])\+geoview([[:space:]]|$)' "$PW2_MK"; then
    echo "ERROR: PassWall2 still has a hard +geoview dependency."
    grep -n 'geoview' "$PW2_MK" || true
    exit 1
fi

echo "===== AFTER PATCH ====="
grep -n 'geoview' "$PW2_MK" || true
