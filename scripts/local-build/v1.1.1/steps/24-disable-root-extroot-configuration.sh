#!/usr/bin/env bash
# Migrated from V1.7 workflow step 24: Disable root extroot configuration
set -e

mkdir -p files/etc/config

cat > files/etc/config/fstab <<'EOF'
config global
        option anon_swap '0'
        option anon_mount '0'
        option auto_swap '1'
        option auto_mount '1'
        option delay_root '5'
        option check_fs '0'
EOF

if grep -Eq \
  "option[[:space:]]+target[[:space:]]+['\"]?/['\"]?" \
  files/etc/config/fstab
then
    echo "ERROR: root extroot target detected"
    exit 1
fi

cat files/etc/config/fstab
