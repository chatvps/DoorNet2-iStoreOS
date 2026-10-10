#!/usr/bin/env bash
# Migrated from V1.7 workflow step 11: Fix Rust 1.80 LLVM bootstrap
set -e

RUST_MK="feeds/packages/lang/rust/Makefile"
test -f "$RUST_MK"

sed -i             's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/g'             "$RUST_MK"

if ! grep -q -- '--set=llvm.download-ci-llvm=false' "$RUST_MK"; then
    echo "ERROR: Rust Makefile was not patched to disable CI LLVM downloads."
    grep -n 'download-ci-llvm' "$RUST_MK" || true
    exit 1
fi

echo "Rust LLVM bootstrap setting:"
grep -n 'download-ci-llvm' "$RUST_MK"
