#!/usr/bin/env bash
# Migrated from V1.7 workflow step 22: Set default LAN IP
set -e

LAN_CONFIG="package/base-files/files/bin/config_generate"

test -f "$LAN_CONFIG"

sed -i \
  's/192\.168\.1\.1/192.168.100.1/g' \
  "$LAN_CONFIG"

grep -n "192\.168\.100\.1" "$LAN_CONFIG" || true
