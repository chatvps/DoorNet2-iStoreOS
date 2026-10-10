#!/usr/bin/env bash
# Migrated from V1.7 workflow step 25: Fix DoorNet2 Linux MMC numbering
set -e

echo "========================================"
echo "Searching DoorNet2 DTS"
echo "========================================"

DTS_FILE="$(
  find target/linux/rockchip \
    -type f \
    -name '*.dts' \
    -print \
  | grep -Ei 'doornet2|door-net2' \
  | head -n 1
)"

if [ -z "$DTS_FILE" ]; then

  DTS_FILE="$(
    grep -RIl \
      --include='*.dts' \
      'embedfire,doornet2' \
      target/linux/rockchip \
      2>/dev/null \
    | head -n 1
  )"

fi

if [ -z "$DTS_FILE" ]; then

  echo "ERROR: DoorNet2 DTS file not found."
  echo
  echo "Possible DTS files:"
  find target/linux/rockchip \
    -type f \
    \( -name '*.dts' -o -name '*.dtsi' \) \
    | grep -Ei 'door|embedfire|rk3399' \
    | head -100

  exit 1
fi


echo "DoorNet2 DTS:"
echo "$DTS_FILE"


export DTS_FILE


python3 <<'PY'
import os
import re
from pathlib import Path

p = Path(os.environ["DTS_FILE"])

s = p.read_text()

marker = "DOORNET2_R18_FIXED_MMC_ALIASES"

if marker in s:
    print("MMC alias patch already present.")
    raise SystemExit(0)


#
# If the board DTS already has an aliases node,
# add/replace mmc0/mmc1 there.
#
alias_match = re.search(
    r'aliases\s*\{',
    s
)

if alias_match:

    start = alias_match.end()

    # Replace existing mapping if present.
    s = re.sub(
        r'\bmmc0\s*=\s*&[^;]+;',
        'mmc0 = &sdmmc;',
        s
    )

    s = re.sub(
        r'\bmmc1\s*=\s*&[^;]+;',
        'mmc1 = &sdhci;',
        s
    )

    # Add missing properties.
    alias_match = re.search(
        r'aliases\s*\{',
        s
    )

    start = alias_match.end()

    addition = "\n"
    addition += "\t\t/* DOORNET2_R18_FIXED_MMC_ALIASES */\n"

    if not re.search(
        r'\bmmc0\s*=\s*&sdmmc\s*;',
        s
    ):
        addition += "\t\tmmc0 = &sdmmc;\n"

    if not re.search(
        r'\bmmc1\s*=\s*&sdhci\s*;',
        s
    ):
        addition += "\t\tmmc1 = &sdhci;\n"

    s = s[:start] + addition + s[start:]

else:

    root = re.search(
        r'/\s*\{',
        s
    )

    if not root:
        raise SystemExit(
            "ERROR: root DTS node not found"
        )

    addition = """
    /* DOORNET2_R18_FIXED_MMC_ALIASES */
    aliases {
            mmc0 = &sdmmc;
            mmc1 = &sdhci;
    };

    """

    pos = root.end()

    s = s[:pos] + "\n" + addition + s[pos:]


p.write_text(s)


final = p.read_text()

if not re.search(
    r'\bmmc0\s*=\s*&sdmmc\s*;',
    final
):
    raise SystemExit(
        "ERROR: mmc0 alias not installed"
    )

if not re.search(
    r'\bmmc1\s*=\s*&sdhci\s*;',
    final
):
    raise SystemExit(
        "ERROR: mmc1 alias not installed"
    )

print("DoorNet2 MMC aliases installed:")
print("  mmc0 = &sdmmc   (TF / fe320000.mmc)")
print("  mmc1 = &sdhci   (eMMC / fe330000.mmc)")
PY


echo
echo "===== MMC ALIAS RESULT ====="

grep -nE \
  'DOORNET2_R18_FIXED_MMC_ALIASES|mmc0.*sdmmc|mmc1.*sdhci' \
  "$DTS_FILE"
