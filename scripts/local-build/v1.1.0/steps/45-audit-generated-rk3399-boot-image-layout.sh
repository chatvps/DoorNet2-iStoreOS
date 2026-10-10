#!/usr/bin/env bash
# Migrated from V1.7 workflow step 45: Audit generated RK3399 boot image layout
set -e

EXT4_IMG="$(find ./bin/targets/rockchip/armv8 -maxdepth 1 -type f -name '*embedfire_doornet2-ext4-sysupgrade.img.gz' | head -n 1)"
[ -n "$EXT4_IMG" ] || { echo "ERROR: ext4 sysupgrade image missing."; exit 1; }

echo "===== EXACT PROVEN R4 RAW BOOTLOADER CHECK ====="
HEAD32_SHA="$(
  gzip -dc "$EXT4_IMG" 2>/dev/null \
    | dd bs=1M count=32 iflag=fullblock status=none \
    | sha256sum \
    | awk '{print $1}'
)"
echo "Generated first 32 MiB: $HEAD32_SHA"
test "$HEAD32_SHA" = "1f10125d602a6ac4a77e4fc136c53f94cd4501730c47a0f60c0b651cfd1e7a04" || {
    echo "ERROR: final image does not contain the exact real-device-proven R4 bootloader area."
    exit 1
}
echo "OK: final first 32 MiB exactly matches the proven 9d1be44 R4 image."

TMP_HEAD="$(mktemp)"
trap 'rm -f "$TMP_HEAD"' EXIT

# Do NOT use `gzip -dc | dd bs=1M count=16` here.  When dd reads from
# a pipe, a short read still counts as one input block unless
# iflag=fullblock is used.  The old v3.0 audit therefore often copied
# far less than 16 MiB, so sector 16384 (8 MiB) was outside the
# temporary file and produced a false "U-Boot missing" result.
python3 - "$EXT4_IMG" "$TMP_HEAD" <<'PY'
import gzip
import os
import sys

src, dst = sys.argv[1:3]
limit = 16 * 1024 * 1024
total = 0

with gzip.open(src, 'rb') as inp, open(dst, 'wb') as out:
    while total < limit:
        chunk = inp.read(min(1024 * 1024, limit - total))
        if not chunk:
            break
        out.write(chunk)
        total += len(chunk)

print(f"Extracted boot-image prefix: {total} bytes")
if total < limit:
    raise SystemExit(
        f"ERROR: decompressed image prefix is only {total} bytes; "
        f"need at least {limit} bytes for the 8 MiB U-Boot audit."
    )
PY

test "$(stat -c '%s' "$TMP_HEAD")" -eq 16777216

echo "===== RK3399 IDB LOADER @ sector 64 ====="
dd if="$TMP_HEAD" bs=512 skip=64 count=8 status=none | hexdump -C | head -40 || true
dd if="$TMP_HEAD" bs=512 skip=64 count=8 status=none | strings | grep -q 'RK33' || {
    echo "ERROR: RK3399 IDB loader signature RK33 not found at sector 64."
    exit 1
}

echo "===== RK3399 SECOND-STAGE U-BOOT @ sector 16384 ====="
dd if="$TMP_HEAD" bs=512 skip=16384 count=16 status=none | hexdump -C | head -40 || true

python3 - "$TMP_HEAD" <<'PY'
import sys

path = sys.argv[1]
offset = 16384 * 512
with open(path, 'rb') as f:
    f.seek(offset)
    data = f.read(8192)

if len(data) != 8192:
    raise SystemExit(
        f"ERROR: could not read second-stage U-Boot region at 8 MiB; got {len(data)} bytes."
    )

if data.startswith(b'LOADER  '):
    print('OK: legacy Rockchip LOADER/uboot.img found at sector 16384.')
elif data.startswith(bytes.fromhex('d00dfeed')):
    print('OK: U-Boot FIT/ITB found at sector 16384.')
else:
    head = data[:32].hex(' ')
    if not any(data):
        reason = 'region is all zero'
    else:
        reason = f'unrecognized header: {head}'
    raise SystemExit(
        'ERROR: valid second-stage U-Boot was not found at sector 16384; ' + reason
    )
PY

echo "OK: RK3399 first-stage and second-stage bootloader regions are present in the generated image."
