#!/usr/bin/env bash
# Migrated from V1.7 workflow step 29: Configure R18 TF first boot
set -e

cat > target/linux/rockchip/image/doornet2.bootscript <<'EOF'
#
# DoorNet2 r18 stable TF/eMMC boot
#
# U-Boot:
#   mmc 1 = TF
#   mmc 0 = eMMC
#
# Linux DT aliases:
#   mmc0 = &sdmmc
#   mmc1 = &sdhci
#
# Linux:
#   TF   = /dev/mmcblk0
#   eMMC = /dev/mmcblk1
#

if test "${stdout}" = "serial@fe660000"; then
    setenv serial_addr ",0xfe660000";
elif test "${stdout}" = "serial@feb50000"; then
    setenv serial_addr ",0xfeb50000";
elif test "${stdout}" = "serial@ff130000"; then
    setenv serial_addr ",0xff130000";
elif test "${stdout}" = "serial@ff1a0000"; then
    setenv serial_addr ",0xff1a0000";
else
    setenv serial_addr "";
fi;

echo "========================================";
echo "DoorNet2 r18 smart boot";
echo "Priority: TF -> eMMC";
echo "Linux: TF=mmcblk0 eMMC=mmcblk1";
echo "========================================";

echo "Trying TF via U-Boot mmc 1:1";

if load mmc 1:1 ${kernel_addr_r} kernel.img; then

    echo "TF kernel found";
    echo "Linux root=/dev/mmcblk0p2";

    setenv rootdev "/dev/mmcblk0p2";

    setenv bootargs "coherent_pool=2M console=ttyS2,1500000 earlycon=uart8250,mmio32${serial_addr} root=${rootdev} rw rootwait";

    bootm ${kernel_addr_r};

    echo "WARNING: TF boot returned unexpectedly";
    echo "Trying eMMC";

else

    echo "TF kernel not found";
    echo "Fallback to eMMC";

fi;


echo "Trying eMMC via U-Boot mmc 0:1";

if load mmc 0:1 ${kernel_addr_r} kernel.img; then

    echo "eMMC kernel found";
    echo "Linux root=/dev/mmcblk1p2";

    setenv rootdev "/dev/mmcblk1p2";

    setenv bootargs "coherent_pool=2M console=ttyS2,1500000 earlycon=uart8250,mmio32${serial_addr} root=${rootdev} rw rootwait";

    bootm ${kernel_addr_r};

else

    echo "FATAL: eMMC kernel not found";

fi;


echo "========================================";
echo "FATAL: No bootable DoorNet2 system";
echo "========================================";
EOF


python3 <<'PY'
from pathlib import Path

p = Path(
    "target/linux/rockchip/image/armv8.mk"
)

s = p.read_text()

marker = "define Device/embedfire_doornet2"

start = s.find(marker)

if start == -1:
    raise SystemExit(
        "ERROR: DoorNet2 block not found"
    )

end = s.find("endef", start)

if end == -1:
    raise SystemExit(
        "ERROR: DoorNet2 block incomplete"
    )

block = s[start:end]

if "BOOT_SCRIPT := doornet2" not in block:

    if "BOOT_FLOW := pine64-bin" not in block:
        raise SystemExit(
            "ERROR: BOOT_FLOW not found"
        )

    block = block.replace(
        "  BOOT_FLOW := pine64-bin\n",
        "  BOOT_FLOW := pine64-bin\n"
        "  BOOT_SCRIPT := doornet2\n"
    )

    s = s[:start] + block + s[end:]

    p.write_text(s)

print(
    p.read_text()[
        start:
        p.read_text().find(
            "endef",
            start
        ) + 5
    ]
)
PY


echo
echo "===== R18 BOOT SCRIPT ====="

cat target/linux/rockchip/image/doornet2.bootscript


echo
echo "===== BOOT VERIFY ====="

grep -q \
  'rootdev "/dev/mmcblk0p2"' \
  target/linux/rockchip/image/doornet2.bootscript

grep -q \
  'rootdev "/dev/mmcblk1p2"' \
  target/linux/rockchip/image/doornet2.bootscript

if grep -Eq \
  '^[[:space:]]*(mmc dev|mmc rescan|part uuid)' \
  target/linux/rockchip/image/doornet2.bootscript
then
    echo "ERROR: unsupported boot command found"
    exit 1
fi
