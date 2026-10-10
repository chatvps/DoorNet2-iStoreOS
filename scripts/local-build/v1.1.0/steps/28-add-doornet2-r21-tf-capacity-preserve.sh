#!/usr/bin/env bash
# Migrated from V1.7 workflow step 28: Add DoorNet2 R21 TF capacity preserve
set -e

PLATFORM="target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh"

test -f "$PLATFORM"

cp -f \
  "$PLATFORM" \
  "${PLATFORM}.upstream-r21-backup"

cat > "$PLATFORM" <<'EOF'
# DOORNET2_R21_TF_CAPACITY_PRESERVE_V1
#
# DoorNet2 TF capacity-preserving sysupgrade.
#
# Physical mapping after the R18 MMC alias fix:
#   Linux mmcblk0 = TF   = SD  = fe320000.mmc
#   Linux mmcblk1 = eMMC = MMC = fe330000.mmc
#
# The firmware image intentionally keeps a 7 GiB p2 so that
# the same image also fits the 7.3 GiB eMMC.
#
# If TF p2 has already been expanded, preserve its partition
# table and grow the newly-written ext4 filesystem to the
# existing large p2 size from the sysupgrade RAMFS.

RAMFS_COPY_BIN="$RAMFS_COPY_BIN /usr/sbin/e2fsck /usr/sbin/resize2fs"


doornet2_is_tf_disk()
{
    local diskdev="$1"
    local board
    local media
    local path

    [ "$diskdev" = "mmcblk0" ] || return 1

    [ -r /tmp/sysinfo/board_name ] || return 1

    board="$(
        cat /tmp/sysinfo/board_name \
            2>/dev/null
    )"

    [ "$board" = "embedfire,doornet2" ] || return 1

    [ -r "/sys/class/block/${diskdev}/device/type" ] \
        || return 1

    media="$(
        cat "/sys/class/block/${diskdev}/device/type" \
            2>/dev/null
    )"

    [ "$media" = "SD" ] || return 1

    path="$(
        /bin/busybox readlink -f \
            "/sys/class/block/${diskdev}/device" \
            2>/dev/null
    )"

    case "$path" in
        *fe320000.mmc*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


doornet2_tf_can_preserve_partitions()
{
    local diskdev="$1"

    local boot1
    local image1
    local boot2
    local image2

    local boot2_start
    local boot2_size
    local image2_start
    local image2_size

    doornet2_is_tf_disk "$diskdev" || return 1

    [ -s /tmp/partmap.bootdisk ] || return 1
    [ -s /tmp/partmap.image ] || return 1

    #
    # DoorNet2 image must contain only p1 and p2.
    #
    if awk '$1 > 2 { found=1 } END { exit(found ? 0 : 1) }' \
        /tmp/partmap.bootdisk
    then
        return 1
    fi

    if awk '$1 > 2 { found=1 } END { exit(found ? 0 : 1) }' \
        /tmp/partmap.image
    then
        return 1
    fi

    boot1="$(
        awk \
            '$1 == 1 { print $2 ":" $3; exit }' \
            /tmp/partmap.bootdisk
    )"

    image1="$(
        awk \
            '$1 == 1 { print $2 ":" $3; exit }' \
            /tmp/partmap.image
    )"

    boot2="$(
        awk \
            '$1 == 2 { print $2 ":" $3; exit }' \
            /tmp/partmap.bootdisk
    )"

    image2="$(
        awk \
            '$1 == 2 { print $2 ":" $3; exit }' \
            /tmp/partmap.image
    )"

    [ -n "$boot1" ] || return 1
    [ -n "$image1" ] || return 1
    [ -n "$boot2" ] || return 1
    [ -n "$image2" ] || return 1

    #
    # p1 start + size must be identical.
    #
    [ "$boot1" = "$image1" ] || return 1

    boot2_start="${boot2%%:*}"
    boot2_size="${boot2##*:}"

    image2_start="${image2%%:*}"
    image2_size="${image2##*:}"

    #
    # p2 may differ ONLY by being larger.
    # The start sector must never move.
    #
    [ "$boot2_start" = "$image2_start" ] || return 1
    [ "$boot2_size" -gt "$image2_size" ] || return 1

    return 0
}


doornet2_tf_grow_ext4()
{
    local diskdev="$1"
    local rootpart
    local rc

    doornet2_is_tf_disk "$diskdev" || return 1

    if ! export_partdevice rootpart 2; then
        echo "DoorNet2: unable to locate TF root partition"
        return 1
    fi

    echo "DoorNet2: checking /dev/${rootpart} before ext4 grow"

    /usr/sbin/e2fsck \
        -f \
        -y \
        "/dev/${rootpart}"

    rc=$?

    case "$rc" in
        0|1)
            ;;
        *)
            echo "DoorNet2: e2fsck failed before grow, rc=${rc}"
            return 1
            ;;
    esac

    echo "DoorNet2: growing ext4 to current TF p2 size"

    if ! /usr/sbin/resize2fs \
        "/dev/${rootpart}"
    then
        echo "DoorNet2: resize2fs failed"
        return 1
    fi

    echo "DoorNet2: checking /dev/${rootpart} after ext4 grow"

    /usr/sbin/e2fsck \
        -f \
        -y \
        "/dev/${rootpart}"

    rc=$?

    case "$rc" in
        0|1)
            ;;
        *)
            echo "DoorNet2: e2fsck failed after grow, rc=${rc}"
            return 1
            ;;
    esac

    sync

    return 0
}


platform_check_image()
{
    local diskdev
    local partdev
    local diff
    local preserve_tf=0

    export_bootdevice && \
    export_partdevice diskdev 0 || {
        echo "Unable to determine upgrade device"
        return 1
    }

    get_partitions \
        "/dev/${diskdev}" \
        bootdisk

    #
    # Extract the boot sector from the image.
    #
    get_image "$@" |
        dd \
            of=/tmp/image.bs \
            count=1 \
            bs=512b \
            2>/dev/null

    get_partitions \
        /tmp/image.bs \
        image

    diff="$(
        grep \
            -F \
            -x \
            -v \
            -f /tmp/partmap.bootdisk \
            /tmp/partmap.image
    )"

    if [ -n "$diff" ] && \
       doornet2_tf_can_preserve_partitions \
           "$diskdev"
    then
        preserve_tf=1
    fi

    rm -f \
        /tmp/image.bs \
        /tmp/partmap.bootdisk \
        /tmp/partmap.image

    if [ "$preserve_tf" = "1" ]; then
        echo "DoorNet2: expanded TF p2 detected."
        echo "DoorNet2: TF partition table will be preserved."
        return 0
    fi

    if [ -n "$diff" ]; then
        echo "Partition layout has changed. Full image will be written."
        ask_bool 0 "Abort" && exit 1
        return 0
    fi

    return 0
}


platform_copy_config()
{
    local partdev

    if export_partdevice partdev 1; then

        mount \
            -o rw,noatime \
            "/dev/${partdev}" \
            /mnt

        cp \
            -af \
            "$UPGRADE_BACKUP" \
            "/mnt/$BACKUP_FILE"

        umount /mnt
    fi
}


platform_do_upgrade()
{
    local diskdev
    local partdev
    local diff
    local preserve_tf=0

    export_bootdevice && \
    export_partdevice diskdev 0 || {
        echo "Unable to determine upgrade device"
        return 1
    }

    sync

    if [ "$UPGRADE_OPT_SAVE_PARTITIONS" = "1" ]; then

        get_partitions \
            "/dev/${diskdev}" \
            bootdisk

        #
        # Extract the boot sector from the image.
        #
        get_image "$@" |
            dd \
                of=/tmp/image.bs \
                count=1 \
                bs=512b

        get_partitions \
            /tmp/image.bs \
            image

        diff="$(
            grep \
                -F \
                -x \
                -v \
                -f /tmp/partmap.bootdisk \
                /tmp/partmap.image
        )"

    else

        diff=1

    fi


    if [ -n "$diff" ] && \
       [ "$UPGRADE_OPT_SAVE_PARTITIONS" = "1" ] && \
       doornet2_tf_can_preserve_partitions \
           "$diskdev"
    then

        preserve_tf=1
        diff=""

        echo "DoorNet2: preserving expanded TF partition table."

    fi


    if [ -n "$diff" ]; then

        get_image "$@" |
            dd \
                of="/dev/${diskdev}" \
                bs=4096 \
                conv=fsync

        #
        # Separate removal and addition is necessary.
        #
        partx \
            -d \
            - \
            "/dev/${diskdev}"

        partx \
            -a \
            - \
            "/dev/${diskdev}"

        return 0
    fi


    #
    # Keep the current partition table and write the image
    # contents into each existing partition.
    #
    while read part start size
    do

        if export_partdevice \
            partdev \
            "$part"
        then

            echo "Writing image to /dev/${partdev}..."

            get_image "$@" |
                dd \
                    of="/dev/${partdev}" \
                    ibs=512 \
                    obs=1M \
                    skip="$start" \
                    count="$size" \
                    conv=fsync

        else

            echo "Unable to find partition ${part} device, skipped."

        fi

    done < /tmp/partmap.image


    #
    # Copy the image disk signature / MBR UUID.
    #
    echo "Writing new UUID to /dev/${diskdev}..."

    get_image "$@" |
        dd \
            of="/dev/${diskdev}" \
            bs=1 \
            skip=440 \
            count=4 \
            seek=440 \
            conv=fsync


    #
    # Only an already-expanded, physically verified TF reaches
    # this branch. The partition itself stays large; resize the
    # newly-written 7 GiB ext4 filesystem back to that size.
    #
    if [ "$preserve_tf" = "1" ]; then

        echo "DoorNet2: restoring ext4 to expanded TF capacity."

        if ! doornet2_tf_grow_ext4 \
            "$diskdev"
        then

            echo "WARNING: DoorNet2 TF ext4 auto-grow failed."
            echo "WARNING: Firmware was written successfully."
            echo "WARNING: TF filesystem can be grown manually later."

        fi

    fi

    return 0
}
EOF

echo "===== R21 PLATFORM SYNTAX ====="

sh -n "$PLATFORM"

echo
echo "===== R21 TF CAPACITY PATCH ====="

grep -nE \
  'DOORNET2_R21_TF_CAPACITY_PRESERVE_V1|RAMFS_COPY_BIN|doornet2_is_tf_disk|doornet2_tf_can_preserve_partitions|doornet2_tf_grow_ext4|preserving expanded TF partition table|resize2fs' \
  "$PLATFORM"

grep -q \
  'DOORNET2_R21_TF_CAPACITY_PRESERVE_V1' \
  "$PLATFORM"

grep -q \
  'fe320000.mmc' \
  "$PLATFORM"

grep -q \
  '/usr/sbin/e2fsck' \
  "$PLATFORM"

grep -q \
  '/usr/sbin/resize2fs' \
  "$PLATFORM"

grep -q \
  'preserving expanded TF partition table' \
  "$PLATFORM"

echo "R21 TF CAPACITY PATCH OK"
