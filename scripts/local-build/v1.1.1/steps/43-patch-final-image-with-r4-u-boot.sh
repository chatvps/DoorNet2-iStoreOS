#!/usr/bin/env bash
# Migrated from V1.7 workflow step 43: Patch final image with R4 U-Boot
set -euo pipefail

ASSET="${GITHUB_WORKSPACE}/r4.bin.gz"
EXPECTED_PATCH_SHA="6cd741e71a65802062ecf134d1dd5f33269c02ccea90a203231a84bdcc7d228a"
EXPECTED_HEAD32_SHA="1f10125d602a6ac4a77e4fc136c53f94cd4501730c47a0f60c0b651cfd1e7a04"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PATCH_BIN="${WORKDIR}/r4-uboot-8-12MiB.bin"
gzip -dc "$ASSET" > "$PATCH_BIN"

test "$(stat -c%s "$PATCH_BIN")" -eq $((4 * 1024 * 1024)) || {
    echo "ERROR: proven R4 U-Boot region must be exactly 4 MiB."
    exit 1
}

echo "${EXPECTED_PATCH_SHA}  ${PATCH_BIN}" | sha256sum -c -

# Always use host-side OpenWrt tools on the x86_64 GitHub runner.
FWTOOL="${GITHUB_WORKSPACE}/staging_dir/host/bin/fwtool"
USIGN="${GITHUB_WORKSPACE}/staging_dir/host/bin/usign"
UCERT="${GITHUB_WORKSPACE}/staging_dir/host/bin/ucert"

# ucert invokes usign by command name; expose OpenWrt host tools.
export PATH="${GITHUB_WORKSPACE}/staging_dir/host/bin:${PATH}"

for TOOL in "$FWTOOL" "$USIGN" "$UCERT"; do
    if [ ! -x "$TOOL" ]; then
        echo "ERROR: required OpenWrt host tool is missing or not executable:"
        echo "       $TOOL"
        exit 1
    fi

    TOOL_INFO="$(file -b "$TOOL" 2>/dev/null || true)"
    echo "$TOOL: $TOOL_INFO"

    case "$TOOL_INFO" in
        *ARM*|*aarch64*|*AArch64*)
            echo "ERROR: target-architecture tool was selected instead of host tool:"
            echo "       $TOOL"
            exit 1
            ;;
    esac
done

# The build system uses the active signing keypair and generates key-build.ucert.
BUILD_KEY="${GITHUB_WORKSPACE}/key-build"
BUILD_PUB="${GITHUB_WORKSPACE}/key-build.pub"
BUILD_UCERT="${GITHUB_WORKSPACE}/key-build.ucert"

for KEYFILE in "$BUILD_KEY" "$BUILD_PUB" "$BUILD_UCERT"; do
    test -s "$KEYFILE" || {
        echo "ERROR: required signing material missing after build: $KEYFILE"
        exit 1
    }
done

# Do not manufacture a synthetic certificate test here. V1.4 proved
# that such a test can be less portable than the real OpenWrt image
# signing path. Instead, validate the ACTUAL generated sysupgrade image
# signature below before any byte is modified.
if ! BUILD_FINGERPRINT="$("$USIGN" -F -p "$BUILD_PUB")"; then
    echo "ERROR: usign could not read key-build.pub."
    exit 1
fi

test -n "$BUILD_FINGERPRINT" || {
    echo "ERROR: empty signing-key fingerprint."
    exit 1
}

echo "Build signing fingerprint: $BUILD_FINGERPRINT"

mapfile -t IMAGES < <(
  find ./bin/targets/rockchip/armv8 \
    -maxdepth 1 -type f \
    -name '*embedfire_doornet2-*-sysupgrade.img.gz' \
    | sort
)

[ "${#IMAGES[@]}" -gt 0 ] || {
    echo "ERROR: no DoorNet2 sysupgrade images were generated."
    exit 1
}

IMAGE_INDEX=0

for IMG_GZ in "${IMAGES[@]}"; do
    IMAGE_INDEX=$((IMAGE_INDEX + 1))
    echo "============================================================"
    echo "Patching final image: $IMG_GZ"
    echo "============================================================"

    IMAGE_WORK="${WORKDIR}/image-${IMAGE_INDEX}"
    mkdir -p "$IMAGE_WORK"

    META="${IMAGE_WORK}/metadata.json"
    META_CHECK="${IMAGE_WORK}/metadata-check.json"
    ORIGINAL_UCERT="${IMAGE_WORK}/original.ucert"
    NEW_UCERT="${IMAGE_WORK}/new.ucert"
    NEW_UCERT_CHECK="${IMAGE_WORK}/new-check.ucert"
    NEW_SIG="${IMAGE_WORK}/new.sig"
    KEYDIR="${IMAGE_WORK}/keys"
    PURE_GZ="${IMAGE_WORK}/payload.img.gz"
    VERIFY_GZ="${IMAGE_WORK}/verify.img.gz"
    RAW="${IMAGE_WORK}/payload.img"
    NEW_GZ="${IMG_GZ}.new"

    rm -f "$NEW_GZ"

    # Preserve OpenWrt metadata before changing the compressed payload.
    if ! "$FWTOOL" -q -i "$META" "$IMG_GZ"; then
        echo "ERROR: OpenWrt fwtool metadata is missing or unreadable: $IMG_GZ"
        exit 1
    fi

    test -s "$META" || {
        echo "ERROR: extracted OpenWrt metadata is empty: $IMG_GZ"
        exit 1
    }

    python3 - "$META" <<'PY_META'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

metadata_version = data.get("metadata_version")
supported_devices = data.get("supported_devices", [])

print("OpenWrt metadata version:", metadata_version)
print("Supported devices:", supported_devices)

if metadata_version != "1.1":
    raise SystemExit(
        f"ERROR: unexpected OpenWrt metadata_version: {metadata_version!r}"
    )

if "embedfire,doornet2" not in supported_devices:
    raise SystemExit(
        "ERROR: final image metadata does not identify embedfire,doornet2"
    )
PY_META

    # Detect whether the original image was signed.
    ORIGINAL_SIGNED=0
    if "$FWTOOL" -q -s "$ORIGINAL_UCERT" "$IMG_GZ" >/dev/null 2>&1; then
        if [ -s "$ORIGINAL_UCERT" ]; then
            ORIGINAL_SIGNED=1
            echo "Original image signature: present"
        fi
    fi

    if [ "$ORIGINAL_SIGNED" -eq 1 ]; then
        # The byte patch invalidates the old signature. Before touching
        # the image, verify the REAL signature produced by OpenWrt using
        # the exact public key from this build. This validates the actual
        # key-build / key-build.ucert / fwtool / ucert chain.
        for KEYFILE in "$BUILD_KEY" "$BUILD_PUB" "$BUILD_UCERT"; do
            if [ ! -s "$KEYFILE" ]; then
                echo "ERROR: signed image detected but build signing material is missing:"
                echo "       $KEYFILE"
                exit 1
            fi
        done

        ORIGINAL_KEYDIR="${IMAGE_WORK}/original-keys"
        mkdir -p "$ORIGINAL_KEYDIR"
        cp -f "$BUILD_PUB" "${ORIGINAL_KEYDIR}/${BUILD_FINGERPRINT}"

        if ! "$FWTOOL" -q -T -s /dev/null "$IMG_GZ" \
            | "$UCERT" -V -m - -c "$ORIGINAL_UCERT" -P "$ORIGINAL_KEYDIR"; then
            echo "ERROR: original OpenWrt sysupgrade signature does not verify"
            echo "       against this build's key-build.pub."
            exit 1
        fi

        echo "OK: original OpenWrt sysupgrade signature verified."
    else
        echo "Original image signature: absent"
        echo "ERROR: CONFIG_SIGN_FIRMWARE was expected to produce a signed image."
        exit 1
    fi

    # OpenWrt image helpers strip signature first, then metadata.
    # Do the same on a working copy so gzip sees only the gzip stream.
    cp -f "$IMG_GZ" "$PURE_GZ"

    "$FWTOOL" -s /dev/null -t "$PURE_GZ" >/dev/null 2>&1 || true

    if ! "$FWTOOL" -i /dev/null -t "$PURE_GZ" >/dev/null 2>&1; then
        echo "ERROR: could not strip OpenWrt image metadata."
        exit 1
    fi

    gzip -t "$PURE_GZ"
    gzip -dc "$PURE_GZ" > "$RAW"

    test "$(stat -c%s "$RAW")" -gt $((32 * 1024 * 1024)) || {
        echo "ERROR: generated image is unexpectedly smaller than 32 MiB: $IMG_GZ"
        exit 1
    }

    # Patch ONLY the proven R4 8..12 MiB U-Boot region.
    dd if="$PATCH_BIN" of="$RAW" bs=1M seek=8 conv=notrunc status=none

    REGION_SHA="$(
      dd if="$RAW" bs=1M skip=8 count=4 iflag=fullblock status=none \
        | sha256sum | awk '{print $1}'
    )"

    echo "8..12 MiB SHA256: $REGION_SHA"

    test "$REGION_SHA" = "$EXPECTED_PATCH_SHA" || {
        echo "ERROR: patched 8..12 MiB R4 U-Boot region verification failed."
        exit 1
    }

    HEAD32_SHA="$(
      dd if="$RAW" bs=1M count=32 iflag=fullblock status=none \
        | sha256sum | awk '{print $1}'
    )"

    echo "First 32 MiB SHA256: $HEAD32_SHA"

    test "$HEAD32_SHA" = "$EXPECTED_HEAD32_SHA" || {
        echo "ERROR: first 32 MiB still differs from the proven R4 boot area."
        echo "Do NOT bypass this check; investigate the remaining boot-area difference."
        exit 1
    }

    # Recompress the patched raw disk image and restore the exact
    # original OpenWrt metadata.
    gzip -n -c "$RAW" > "$NEW_GZ"
    "$FWTOOL" -I "$META" "$NEW_GZ"

    # If the original build produced a signed image, generate a fresh
    # signature AFTER the patch and metadata restore. This mirrors:
    #   usign -S -> ucert -A -> fwtool -S
    # from OpenWrt's normal Build/append-metadata implementation.
    if [ "$ORIGINAL_SIGNED" -eq 1 ]; then
        cp -f "$BUILD_UCERT" "$NEW_UCERT"

        if ! "$USIGN" \
          -S \
          -m "$NEW_GZ" \
          -s "$BUILD_KEY" \
          -x "$NEW_SIG"; then
            echo "ERROR: usign failed while signing rebuilt image."
            exit 1
        fi

        UCERT_SIZE_BEFORE="$(stat -c%s "$NEW_UCERT")"

        UCERT_APPEND_RC=0
        "$UCERT" -A -c "$NEW_UCERT" -x "$NEW_SIG" || UCERT_APPEND_RC=$?

        UCERT_SIZE_AFTER="$(stat -c%s "$NEW_UCERT")"

        echo "ucert append exit code: $UCERT_APPEND_RC"
        echo "ucert size before append: $UCERT_SIZE_BEFORE"
        echo "ucert size after append:  $UCERT_SIZE_AFTER"

        if [ "$UCERT_SIZE_AFTER" -le "$UCERT_SIZE_BEFORE" ]; then
            echo "ERROR: rebuilt image signature was not appended to ucert."
            exit 1
        fi

        case "$UCERT_APPEND_RC" in
            0|1)
                ;;
            *)
                echo "ERROR: unexpected ucert append exit code: $UCERT_APPEND_RC"
                exit 1
                ;;
        esac

        echo "OK: rebuilt image signature appended to ucert."

        if ! "$FWTOOL" -S "$NEW_UCERT" "$NEW_GZ"; then
            echo "ERROR: fwtool failed while attaching rebuilt image certificate."
            exit 1
        fi

        # Extract and cryptographically verify the newly appended
        # certificate/signature against this build's public key.
        if ! "$FWTOOL" -q -s "$NEW_UCERT_CHECK" "$NEW_GZ"; then
            echo "ERROR: rebuilt image signature cannot be extracted."
            exit 1
        fi

        test -s "$NEW_UCERT_CHECK" || {
            echo "ERROR: rebuilt image signature trailer is empty."
            exit 1
        }

        mkdir -p "$KEYDIR"
        KEY_FINGERPRINT="$("$USIGN" -F -p "$BUILD_PUB")"
        test -n "$KEY_FINGERPRINT"
        cp -f "$BUILD_PUB" "${KEYDIR}/${KEY_FINGERPRINT}"

        if ! "$FWTOOL" -q -T -s /dev/null "$NEW_GZ" \
            | "$UCERT" -V -m - -c "$NEW_UCERT_CHECK" -P "$KEYDIR"; then
            echo "ERROR: rebuilt image signature verification failed."
            exit 1
        fi

        echo "OK: rebuilt OpenWrt firmware signature verified."
    fi

    # Confirm metadata is still readable and byte-for-byte identical.
    if ! "$FWTOOL" -q -i "$META_CHECK" "$NEW_GZ"; then
        echo "ERROR: restored OpenWrt metadata cannot be read."
        exit 1
    fi

    if ! cmp -s "$META" "$META_CHECK"; then
        echo "ERROR: OpenWrt metadata changed while rebuilding the image."
        exit 1
    fi

    # Validate gzip payload one final time after stripping any fresh
    # signature and metadata trailers from a temporary copy.
    cp -f "$NEW_GZ" "$VERIFY_GZ"
    "$FWTOOL" -s /dev/null -t "$VERIFY_GZ" >/dev/null 2>&1 || true

    if ! "$FWTOOL" -i /dev/null -t "$VERIFY_GZ" >/dev/null 2>&1; then
        echo "ERROR: could not strip metadata from rebuilt image for gzip verification."
        exit 1
    fi

    gzip -t "$VERIFY_GZ"

    mv -f "$NEW_GZ" "$IMG_GZ"
    rm -rf "$IMAGE_WORK"

    echo "OK: patched image, preserved metadata, and restored valid signature: $IMG_GZ"
done

echo "OK: all DoorNet2 final images contain the proven R4 8..12 MiB U-Boot region."
echo "OK: all DoorNet2 final images preserve readable OpenWrt fwtool metadata."
echo "OK: signed input images are re-signed and verified after the U-Boot patch."
