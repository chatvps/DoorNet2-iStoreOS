#!/usr/bin/env bash
# Migrated from V1.7 workflow step 14: Pin PassWall Go cores for DoorNet2 Go 1.23
set -e

echo "===== DOORNET2 GO 1.23 PASSWALL COMPATIBILITY ====="

# This legacy/stable LEDE tree provides Go 1.23.1.
# Current PassWall packages track newer Go applications:
#   sing-box 1.14.0      -> Go >= 1.25.5
#   v2ray-plugin 5.49.0 -> Go >= 1.25.5
#   current Xray        -> newer Go toolchain
#
# R32 therefore keeps Xray as the built-in PassWall core, pins it to
# Xray 25.1.30 (go.mod: go 1.23), and disables Sing-box/v2ray-plugin
# in the firmware configuration below. Do not replace the whole Go
# toolchain: TF-first/eMMC fallback and the R23 stable buildroot stay
# untouched.

XRAY_MK="feeds/passwall_packages/xray-core/Makefile"
test -f "$XRAY_MK"

sed -i \
  's/^PKG_VERSION:=.*/PKG_VERSION:=25.1.30/' \
  "$XRAY_MK"

sed -i \
  's/^PKG_HASH:=.*/PKG_HASH:=983ee395f085ed1b7fbe0152cb56a5b605a6f70a5645d427c7186c476f14894e/' \
  "$XRAY_MK"

# PassWall's current Xray Makefile injects core.version, which exists
# in newer Xray but not in v25.1.30. Keep only core.build for the
# pinned release.
export XRAY_MK
python3 <<'PY_XRAY'
import os
from pathlib import Path

p = Path(os.environ["XRAY_MK"])
lines = p.read_text().splitlines()
out = []

found_build = False
found_version = False

for line in lines:
    if "$(GO_PKG)/core.build=OpenWrt" in line:
        out.append("\t$(GO_PKG)/core.build=OpenWrt")
        found_build = True
        continue

    if "$(GO_PKG)/core.version=$(PKG_VERSION)" in line:
        found_version = True
        continue

    out.append(line)

if not found_build:
    raise SystemExit("ERROR: xray core.build ldflag line not found")

if not found_version:
    raise SystemExit("ERROR: xray core.version ldflag line not found")

p.write_text("\n".join(out) + "\n")
PY_XRAY

grep -q '^PKG_VERSION:=25\.1\.30$' "$XRAY_MK"
grep -q '^PKG_HASH:=983ee395f085ed1b7fbe0152cb56a5b605a6f70a5645d427c7186c476f14894e$' "$XRAY_MK"
grep -q '\$(GO_PKG)/core.build=OpenWrt' "$XRAY_MK"

if grep -q 'core.version=\$(PKG_VERSION)' "$XRAY_MK"; then
    echo "ERROR: incompatible Xray core.version ldflag still present"
    exit 1
fi

echo "Pinned Xray:"
grep -nE '^PKG_(VERSION|HASH):=|GO_PKG_LDFLAGS_X|core\.build|core\.version' "$XRAY_MK"
