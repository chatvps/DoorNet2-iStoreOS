#!/usr/bin/env bash
# Migrated from V1.7 workflow step 42: Compile firmware
set -euo pipefail
make -j"${DOORNET2_JOBS:-2}" || \
  make -j1 V=s

df -h

find ./bin/targets/ \
  -type f \
  | sort
