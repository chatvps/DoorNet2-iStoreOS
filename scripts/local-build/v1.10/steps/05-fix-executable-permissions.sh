#!/usr/bin/env bash
# Migrated from V1.7 workflow step 05: Fix executable permissions
set -e
chmod -R +x scripts || true
find . -type f             \( -name "*.sh" -o -name "*.pl" -o -name "config.guess" -o -name "command_all.sh" \)             -exec chmod +x {} \; || true
chmod +x ./scripts/feeds
