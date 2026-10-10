#!/usr/bin/env bash
# Migrated from V1.7 workflow step 08: Add iStore feed
set -e

grep -q '^src-git istore ' feeds.conf.default || \
  echo 'src-git istore https://github.com/linkease/istore;main' \
  >> feeds.conf.default

cat feeds.conf.default
