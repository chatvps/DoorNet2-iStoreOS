#!/usr/bin/env bash
# Migrated from V1.7 workflow step 39: Verify UU accelerator is completely absent
set -e

if grep -Eq '^CONFIG_PACKAGE_.*(uugamebooster|uuplugin).*=y$' .config; then
    echo "ERROR: UU package selected."
    exit 1
fi

if grep -RniE 'uugamebooster|uuplugin|网易[[:space:]]*UU|NetEase[[:space:]]+UU' files 2>/dev/null; then
    echo "ERROR: UU menu/script/autostart/runtime/update content found in files/."
    exit 1
fi

if grep -RniE 'router\.uu\.163\.com|uu\.gdl\.netease\.com|uurouter\.gdl\.netease\.com' files 2>/dev/null; then
    echo "ERROR: UU-specific domain found in files/."
    exit 1
fi

echo "OK: UU accelerator is absent from final firmware overlay and config."
