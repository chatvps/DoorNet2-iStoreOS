#!/usr/bin/env bash
# Migrated from V1.7 workflow step 46: Audit proven R4 boot invariants
set -euo pipefail

EXT4_IMG="$(find ./bin/targets/rockchip/armv8 -maxdepth 1 -type f -name '*embedfire_doornet2-ext4-sysupgrade.img.gz' | head -n 1)"
[ -n "$EXT4_IMG" ] || { echo "ERROR: ext4 sysupgrade image missing."; exit 1; }

TMP96="$(mktemp)"
P1="$(mktemp)"
BOOTSCR="$(mktemp)"
KERNELIMG="$(mktemp)"
trap 'rm -f "$TMP96" "$P1" "$BOOTSCR" "$KERNELIMG"' EXIT

# Copy exactly the first 96 MiB: 0-32 MiB bootloader region plus
# the complete 64 MiB p1 boot filesystem.
python3 - "$EXT4_IMG" "$TMP96" <<'PY'
import gzip, sys
src, dst = sys.argv[1:3]
limit = 96 * 1024 * 1024
total = 0
with gzip.open(src, 'rb') as inp, open(dst, 'wb') as out:
    while total < limit:
        b = inp.read(min(1024 * 1024, limit - total))
        if not b:
            break
        out.write(b)
        total += len(b)
print(f"Extracted {total} bytes")
if total != limit:
    raise SystemExit(f"ERROR: expected 96 MiB prefix, got {total}")
PY

dd if="$TMP96" of="$P1" bs=1M skip=32 count=64 status=none

# p1 is ext4 and contains boot.scr + kernel.img at filesystem root.
debugfs -R "dump /boot.scr $BOOTSCR" "$P1" >/dev/null 2>&1
debugfs -R "dump /kernel.img $KERNELIMG" "$P1" >/dev/null 2>&1
test -s "$BOOTSCR"
test -s "$KERNELIMG"

echo "===== PROVEN R4 BOOT.SCR PAYLOAD ====="
BOOT_PAYLOAD_SHA="$(tail -c +65 "$BOOTSCR" | sha256sum | awk '{print $1}')"
echo "boot.scr payload SHA256: $BOOT_PAYLOAD_SHA"
test "$BOOT_PAYLOAD_SHA" = "859733899485625e2f7ca6f40d5448fe0d568b2d2fe9d098ef83d46a62b2a0fa" || {
    echo "ERROR: boot.scr payload no longer matches the real-device-proven TF-first/eMMC-fallback R4 script."
    strings "$BOOTSCR" || true
    exit 1
}

echo "===== PROVEN R4 DOORNET2 DTB ====="
python3 - "$KERNELIMG" <<'PY'
import hashlib, struct, sys

path = sys.argv[1]
data = open(path, 'rb').read()
if len(data) < 40:
    raise SystemExit('ERROR: kernel.img too small')

hdr = struct.unpack('>10I', data[:40])
magic, totalsize, off_struct, off_strings, off_mem, version, last_comp, boot_cpu, size_strings, size_struct = hdr
if magic != 0xd00dfeed:
    raise SystemExit('ERROR: kernel.img is not an FDT/FIT image')

strings = data[off_strings:off_strings + size_strings]
p = off_struct
end = off_struct + size_struct
stack = []
fdt_data = None

while p < end:
    token = struct.unpack('>I', data[p:p+4])[0]
    p += 4
    if token == 1:  # FDT_BEGIN_NODE
        q = data.index(b'\0', p)
        name = data[p:q].decode('utf-8', 'replace')
        p = (q + 4) & ~3
        stack.append(name)
    elif token == 2:  # FDT_END_NODE
        stack.pop()
    elif token == 3:  # FDT_PROP
        ln, noff = struct.unpack('>II', data[p:p+8])
        p += 8
        val = data[p:p+ln]
        p = (p + ln + 3) & ~3
        q = strings.index(b'\0', noff)
        prop = strings[noff:q].decode()
        node = '/' + '/'.join(x for x in stack if x)
        if node == '/images/fdt-1' and prop == 'data':
            fdt_data = val
    elif token == 4:  # FDT_NOP
        pass
    elif token == 9:  # FDT_END
        break
    else:
        raise SystemExit(f'ERROR: invalid FIT token {token}')

if fdt_data is None:
    raise SystemExit('ERROR: DoorNet2 DTB not found in kernel FIT')

sha = hashlib.sha256(fdt_data).hexdigest()
print('DoorNet2 DTB size   :', len(fdt_data))
print('DoorNet2 DTB SHA256:', sha)
expected = 'cf8b9b97180c45b547cc9040ff75ca8af0b5dbfac20def223f767f4984dc9d1c'
if sha != expected:
    raise SystemExit('ERROR: generated DoorNet2 DTB differs from the real-device-proven R4 DTB')
print('OK: DoorNet2 DTB matches proven R4 exactly.')
PY

echo "===== R4 KERNEL / KMOD COHERENCE ====="
ROOTFS_TAR="$(find ./bin/targets/rockchip/armv8 -maxdepth 1 -type f \
    \( -name '*embedfire_doornet2-rootfs.tar.gz' -o -name 'openwrt-rockchip-armv8-rootfs.tar.gz' \) | head -n 1)"
[ -n "$ROOTFS_TAR" ] || { echo "ERROR: rootfs tar missing"; exit 1; }

STATUS_PATH="$(tar -tzf "$ROOTFS_TAR" | grep -m1 -E '^(\./)?usr/lib/opkg/status$' || true)"
[ -n "$STATUS_PATH" ] || { echo "ERROR: usr/lib/opkg/status missing from rootfs tar"; exit 1; }

STATUS_TMP="$(mktemp)"
tar -xOzf "$ROOTFS_TAR" "$STATUS_PATH" > "$STATUS_TMP"

MANIFEST="$(find ./bin/targets/rockchip/armv8 -maxdepth 1 -type f \
    -name '*embedfire_doornet2*.manifest' | head -n 1)"

KERNEL_VERSION=""
if [ -n "$MANIFEST" ]; then
    KERNEL_VERSION="$(awk '$1 == "kernel" && $2 == "-" {print $3; exit}' "$MANIFEST")"
fi

if [ -z "$KERNEL_VERSION" ]; then
    KERNEL_VERSION="$(awk 'BEGIN{p=0} /^Package: kernel$/{p=1; next} p && /^Version: /{sub(/^Version: /, ""); print; exit}' "$STATUS_TMP")"
fi

[ -n "$KERNEL_VERSION" ] || { echo "ERROR: could not determine generated kernel ABI"; exit 1; }

echo "Generated kernel ABI : ${KERNEL_VERSION}"
echo "Historical R4 ABI   : ${DOORNET2_R4_KERNEL_ABI}"

if [ "$KERNEL_VERSION" != "$DOORNET2_R4_KERNEL_ABI" ]; then
    echo "NOTICE: kernel package ABI hash differs from historical R4."
    echo "This hash changes when built-in kernel-module/package selections change."
    echo "The V0.1 workflow treats it as diagnostic information, not a bootability verdict."
else
    echo "OK: kernel ABI hash exactly matches historical R4."
fi

python3 - "$STATUS_TMP" "$KERNEL_VERSION" <<'PY_ABI'
import re, sys
path, kernel_version = sys.argv[1:3]
text = open(path, 'r', encoding='utf-8', errors='replace').read()
blocks = [b for b in text.split('\n\n') if b.strip()]
bad = []
kmods = 0
for block in blocks:
    m = re.search(r'(?m)^Package: (kmod-[^\s]+)$', block)
    if not m:
        continue
    kmods += 1
    pkg = m.group(1)
    dep = re.search(r'(?m)^Depends: (.*)$', block)
    if not dep:
        continue
    versions = re.findall(r'kernel \(= ([^)]+)\)', dep.group(1))
    for ver in versions:
        if ver != kernel_version:
            bad.append((pkg, ver))
if bad:
    print('ERROR: installed kmods depend on a different kernel ABI:')
    for pkg, ver in bad[:50]:
        print(f'  {pkg}: {ver}')
    raise SystemExit(1)
print(f'OK: {kmods} installed kmod package records are coherent with kernel {kernel_version}.')
PY_ABI

rm -f "$STATUS_TMP"

if ! strings "$KERNELIMG" | grep -q '6\.6\.66'; then
    echo "ERROR: boot kernel FIT does not contain the required 6.6.66 version marker."
    exit 1
fi

echo "OK: proven R4 boot.scr + byte-identical DoorNet2 DTB + coherent 6.6.66 kernel/modules passed."
