#!/usr/bin/env bash
# Migrated from V1.7 workflow step 31: Add DoorNet2 R18 online updater
set -e

mkdir -p \
  files/usr/bin \
  files/usr/lib/lua/luci/controller \
  files/usr/lib/lua/luci/view/doornet2


cat > files/usr/bin/doornet2-updater <<'EOF'
#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

REPO="chatvps/DoorNet2-iStoreOS"

BASE_URL="https://github.com/${REPO}/releases/latest/download"

WORKDIR="/tmp/doornet2-update"

META="${WORKDIR}/version.json"

FIRMWARE="${WORKDIR}/DoorNet2-ext4-sysupgrade.img.gz"

TESTLOG="/tmp/doornet2-sysupgrade-test.log"

UPGRADELOG="/tmp/doornet2-upgrade.log"

RELEASE_INFO="/etc/doornet2_release"

EXPECTED_BOARD="embedfire,doornet2"

EXPECTED_ASSET="DoorNet2-ext4-sysupgrade.img.gz"


get_current_version()
{
    CURRENT_VERSION="unknown"
    CURRENT_TAG="unknown"

    if [ -f "$RELEASE_INFO" ]; then

        . "$RELEASE_INFO"

        CURRENT_VERSION="${DOORNET2_VERSION:-unknown}"
        CURRENT_TAG="${DOORNET2_TAG:-unknown}"

    fi
}


get_board()
{
    BOARD="unknown"

    if [ -r /tmp/sysinfo/board_name ]; then

        IFS= read -r BOARD \
            < /tmp/sysinfo/board_name

        [ -n "$BOARD" ] || \
            BOARD="unknown"

    fi
}


#
# Check Linux MMC host numbering.
#
# Host mmc0 must be fe320000.mmc (TF controller)
# Host mmc1 must be fe330000.mmc (eMMC controller)
#
# mmc_host exists even when no TF card is inserted.
#
verify_mmc_host_layout()
{
    HOST0=""
    HOST1=""

    HOST0="$(
        readlink -f \
          /sys/class/mmc_host/mmc0/device \
          2>/dev/null
    )"

    HOST1="$(
        readlink -f \
          /sys/class/mmc_host/mmc1/device \
          2>/dev/null
    )"

    case "$HOST0" in
        *fe320000.mmc*)
            ;;
        *)
            return 1
            ;;
    esac

    case "$HOST1" in
        *fe330000.mmc*)
            ;;
        *)
            return 2
            ;;
    esac

    return 0
}


#
# Determine current root and physical media.
#
get_root_info()
{
    ROOT_DEVICE=""
    ROOT_DISK=""
    UPGRADE_DISK="unknown"
    BOOT_MEDIA="unknown"
    MEDIA_TYPE="unknown"
    CONTROLLER="unknown"

    CMDLINE=""

    if [ -r /proc/cmdline ]; then

        IFS= read -r CMDLINE \
            < /proc/cmdline

        for ARG in $CMDLINE; do

            case "$ARG" in

                root=/dev/mmcblk0p2|root=/dev/mmcblk1p2)

                    ROOT_DEVICE="${ARG#root=}"
                    break
                    ;;

            esac

        done

    fi


    if [ -z "$ROOT_DEVICE" ]; then

        ROOT_DEVICE="$(
            /bin/mount 2>/dev/null |
            awk '
                $3 == "/" {
                    print $1
                    exit
                }
            '
        )"

    fi


    case "$ROOT_DEVICE" in

        /dev/mmcblk0p2)

            ROOT_DISK="/dev/mmcblk0"
            ;;

        /dev/mmcblk1p2)

            ROOT_DISK="/dev/mmcblk1"
            ;;

        *)

            return 1
            ;;

    esac


    SYSNAME="${ROOT_DISK#/dev/}"


    if [ -r "/sys/block/${SYSNAME}/device/type" ]; then

        IFS= read -r MEDIA_TYPE \
            < "/sys/block/${SYSNAME}/device/type"

    fi


    CONTROLLER="$(
        readlink -f \
          "/sys/block/${SYSNAME}/device" \
          2>/dev/null
    )"


    case "$ROOT_DEVICE:$MEDIA_TYPE:$CONTROLLER" in

        /dev/mmcblk0p2:SD:*fe320000.mmc*)

            BOOT_MEDIA="TF"
            UPGRADE_DISK="/dev/mmcblk0"
            ;;

        /dev/mmcblk1p2:MMC:*fe330000.mmc*)

            BOOT_MEDIA="eMMC"
            UPGRADE_DISK="/dev/mmcblk1"
            ;;

        *)

            BOOT_MEDIA="unknown"
            UPGRADE_DISK="unknown"
            return 2
            ;;

    esac


    return 0
}


#
# Full upgrade safety guard.
#
verify_sysupgrade_target()
{
    SYSUPGRADE_DISK="unknown"
    TARGET_GUARD_MESSAGE="unknown"


    if ! verify_mmc_host_layout; then

        TARGET_GUARD_MESSAGE="mmc_host_layout_mismatch"
        return 20

    fi


    if ! get_root_info; then

        TARGET_GUARD_MESSAGE="root_media_mismatch"
        return 21

    fi


    EXPECTED_DISKDEV="${UPGRADE_DISK#/dev/}"


    if [ ! -r /lib/functions.sh ]; then

        TARGET_GUARD_MESSAGE="functions_missing"
        return 22

    fi


    if [ ! -r /lib/upgrade/common.sh ]; then

        TARGET_GUARD_MESSAGE="upgrade_common_missing"
        return 23

    fi


    . /lib/functions.sh
    . /lib/upgrade/common.sh


    unset diskdev


    if ! export_bootdevice \
        >/dev/null 2>&1
    then

        TARGET_GUARD_MESSAGE="export_bootdevice_failed"
        return 24

    fi


    if ! export_partdevice \
        diskdev \
        0 \
        >/dev/null 2>&1
    then

        TARGET_GUARD_MESSAGE="export_partdevice_failed"
        return 25

    fi


    SYSUPGRADE_DISK="/dev/${diskdev}"


    if [ "$diskdev" != "$EXPECTED_DISKDEV" ]; then

        TARGET_GUARD_MESSAGE="target_mismatch"
        return 26

    fi


    TARGET_GUARD_MESSAGE="ok"

    return 0
}


fetch_metadata()
{
    mkdir -p "$WORKDIR"

    rm -f "${META}.part"

    if ! curl \
        -LfsS \
        --connect-timeout 15 \
        --retry 3 \
        -o "${META}.part" \
        "${BASE_URL}/version.json"
    then
        return 1
    fi

    mv "${META}.part" "$META"


    LATEST_VERSION="$(
        jsonfilter \
            -i "$META" \
            -e '@.version' \
            2>/dev/null
    )"

    LATEST_TAG="$(
        jsonfilter \
            -i "$META" \
            -e '@.tag' \
            2>/dev/null
    )"

    LATEST_BOARD="$(
        jsonfilter \
            -i "$META" \
            -e '@.board' \
            2>/dev/null
    )"

    LATEST_ASSET="$(
        jsonfilter \
            -i "$META" \
            -e '@.asset' \
            2>/dev/null
    )"

    LATEST_SHA="$(
        jsonfilter \
            -i "$META" \
            -e '@.sha256' \
            2>/dev/null
    )"


    [ "$LATEST_BOARD" = "$EXPECTED_BOARD" ] \
        || return 2

    [ "$LATEST_ASSET" = "$EXPECTED_ASSET" ] \
        || return 3

    [ -n "$LATEST_VERSION" ] \
        || return 4

    echo "$LATEST_SHA" |
        grep -Eq \
          '^[0-9a-fA-F]{64}$' \
        || return 5


    return 0
}


capture_user_state()
{
    # The normal sysupgrade path preserves configuration by default
    # because this updater NEVER uses the -n (discard settings) flag.
    # Save the one service state that is not represented by a normal
    # UCI enabled option: AdGuard Home's /etc/rc.d enable symlink.
    if ls /etc/rc.d/S[0-9][0-9]adguardhome >/dev/null 2>&1; then
        echo 'adguardhome_enabled=1' > /etc/doornet2-upgrade-service-state
    else
        echo 'adguardhome_enabled=0' > /etc/doornet2-upgrade-service-state
    fi

    # The marker prevents clean-install defaults from being applied
    # again after a retained online upgrade.
    touch /etc/doornet2-user-network-initialized
    sync
}


command_status()
{
    get_current_version
    get_board

    HOST_LAYOUT="bad"

    if verify_mmc_host_layout; then
        HOST_LAYOUT="ok"
    fi


    get_root_info || true


    printf '{'
    printf '"ok":true,'
    printf '"current_version":"%s",' "$CURRENT_VERSION"
    printf '"current_tag":"%s",' "$CURRENT_TAG"
    printf '"board":"%s",' "$BOARD"
    printf '"root_device":"%s",' "$ROOT_DEVICE"
    printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
    printf '"boot_media":"%s",' "$BOOT_MEDIA"
    printf '"media_type":"%s",' "$MEDIA_TYPE"
    printf '"mmc_layout":"%s"' "$HOST_LAYOUT"
    printf '}\n'
}


command_check()
{
    get_current_version
    get_board


    if [ "$BOARD" != "$EXPECTED_BOARD" ]; then

        printf \
          '{"ok":false,"message":"board_mismatch"}\n'

        exit 1
    fi


    if ! verify_mmc_host_layout; then

        printf \
          '{"ok":false,"message":"mmc_host_layout_mismatch"}\n'

        exit 1
    fi


    if ! get_root_info; then

        printf \
          '{"ok":false,"message":"root_media_mismatch"}\n'

        exit 1
    fi


    if ! fetch_metadata; then

        printf \
          '{"ok":false,"message":"metadata_download_failed"}\n'

        exit 1
    fi


    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        AVAILABLE="false"
    else
        AVAILABLE="true"
    fi


    printf '{'
    printf '"ok":true,'
    printf '"current_version":"%s",' "$CURRENT_VERSION"
    printf '"latest_version":"%s",' "$LATEST_VERSION"
    printf '"latest_tag":"%s",' "$LATEST_TAG"
    printf '"update_available":%s,' "$AVAILABLE"
    printf '"boot_media":"%s",' "$BOOT_MEDIA"
    printf '"media_type":"%s",' "$MEDIA_TYPE"
    printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
    printf '"mmc_layout":"ok"'
    printf '}\n'
}


command_prepare()
{
    get_board


    if [ "$BOARD" != "$EXPECTED_BOARD" ]; then

        printf \
          '{"ok":false,"message":"board_mismatch"}\n'

        exit 1
    fi


    if ! verify_sysupgrade_target; then

        printf '{'
        printf '"ok":false,'
        printf '"message":"target_guard_failed",'
        printf '"guard_message":"%s",' "$TARGET_GUARD_MESSAGE"
        printf '"boot_media":"%s",' "$BOOT_MEDIA"
        printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
        printf '"sysupgrade_disk":"%s"' "$SYSUPGRADE_DISK"
        printf '}\n'

        exit 1
    fi


    if ! fetch_metadata; then

        printf \
          '{"ok":false,"message":"metadata_download_failed"}\n'

        exit 1
    fi


    rm -f "${FIRMWARE}.part"


    if ! curl \
        -LfsS \
        --connect-timeout 15 \
        --retry 3 \
        -o "${FIRMWARE}.part" \
        "${BASE_URL}/${EXPECTED_ASSET}"
    then

        rm -f "${FIRMWARE}.part"

        printf \
          '{"ok":false,"message":"firmware_download_failed"}\n'

        exit 1
    fi


    mv "${FIRMWARE}.part" "$FIRMWARE"


    ACTUAL_SHA="$(
        sha256sum "$FIRMWARE" |
        awk '{print $1}'
    )"


    if [ "$ACTUAL_SHA" != "$LATEST_SHA" ]; then

        rm -f "$FIRMWARE"

        printf \
          '{"ok":false,"message":"sha256_failed"}\n'

        exit 1
    fi


    rm -f "$TESTLOG"


    if ! /sbin/sysupgrade \
        -T \
        "$FIRMWARE" \
        >"$TESTLOG" 2>&1
    then

        printf \
          '{"ok":false,"message":"sysupgrade_test_failed"}\n'

        exit 1
    fi


    if ! verify_sysupgrade_target; then

        printf '{'
        printf '"ok":false,'
        printf '"message":"target_guard_failed_after_test",'
        printf '"guard_message":"%s",' "$TARGET_GUARD_MESSAGE"
        printf '"boot_media":"%s",' "$BOOT_MEDIA"
        printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
        printf '"sysupgrade_disk":"%s"' "$SYSUPGRADE_DISK"
        printf '}\n'

        exit 1
    fi


    SIZE="$(
        du -h "$FIRMWARE" |
        awk '{print $1}'
    )"


    printf '{'
    printf '"ok":true,'
    printf '"ready":true,'
    printf '"latest_version":"%s",' "$LATEST_VERSION"
    printf '"sha256":"%s",' "$ACTUAL_SHA"
    printf '"size":"%s",' "$SIZE"
    printf '"boot_media":"%s",' "$BOOT_MEDIA"
    printf '"media_type":"%s",' "$MEDIA_TYPE"
    printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
    printf '"sysupgrade_disk":"%s",' "$SYSUPGRADE_DISK"
    printf '"mmc_layout":"ok",'
    printf '"keep_config":true,'
    printf '"target_guard":"ok"'
    printf '}\n'
}


command_upgrade()
{
    get_board


    if [ "$BOARD" != "$EXPECTED_BOARD" ]; then

        printf \
          '{"ok":false,"message":"board_mismatch"}\n'

        exit 1
    fi


    if [ ! -f "$META" ] || \
       [ ! -f "$FIRMWARE" ]
    then

        printf \
          '{"ok":false,"message":"firmware_not_prepared"}\n'

        exit 1
    fi


    LATEST_SHA="$(
        jsonfilter \
            -i "$META" \
            -e '@.sha256' \
            2>/dev/null
    )"


    ACTUAL_SHA="$(
        sha256sum "$FIRMWARE" |
        awk '{print $1}'
    )"


    if [ -z "$LATEST_SHA" ] || \
       [ "$LATEST_SHA" != "$ACTUAL_SHA" ]
    then

        printf \
          '{"ok":false,"message":"sha256_failed"}\n'

        exit 1
    fi


    if ! /sbin/sysupgrade \
        -T \
        "$FIRMWARE" \
        >"$TESTLOG" 2>&1
    then

        printf \
          '{"ok":false,"message":"sysupgrade_test_failed"}\n'

        exit 1
    fi


    #
    # FINAL safety check immediately before writing disk.
    #
    if ! verify_sysupgrade_target; then

        printf '{'
        printf '"ok":false,'
        printf '"message":"final_target_guard_failed",'
        printf '"guard_message":"%s",' "$TARGET_GUARD_MESSAGE"
        printf '"boot_media":"%s",' "$BOOT_MEDIA"
        printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
        printf '"sysupgrade_disk":"%s"' "$SYSUPGRADE_DISK"
        printf '}\n'

        exit 1
    fi


    # Retain current user configuration by default.  OpenWrt
    # sysupgrade preserves settings unless -n is supplied; this updater
    # intentionally never supplies -n.  Capture AdGuard Home's service
    # enable state before the backup/flash phase as well.
    capture_user_state
    sync


    (
        sleep 3

        /sbin/sysupgrade \
          -v \
          "$FIRMWARE"

    ) >"$UPGRADELOG" \
      2>&1 \
      </dev/null &


    printf '{'
    printf '"ok":true,'
    printf '"started":true,'
    printf '"boot_media":"%s",' "$BOOT_MEDIA"
    printf '"upgrade_disk":"%s",' "$UPGRADE_DISK"
    printf '"sysupgrade_disk":"%s",' "$SYSUPGRADE_DISK"
    printf '"keep_config":true,'
    printf '"target_guard":"ok"'
    printf '}\n'
}


case "$1" in

    status)
        command_status
        ;;

    check)
        command_check
        ;;

    prepare)
        command_prepare
        ;;

    upgrade)
        command_upgrade
        ;;

    *)
        echo "Usage:"
        echo "  doornet2-updater status"
        echo "  doornet2-updater check"
        echo "  doornet2-updater prepare"
        echo "  doornet2-updater upgrade"
        exit 1
        ;;

esac
EOF


chmod 755 files/usr/bin/doornet2-updater

sh -n files/usr/bin/doornet2-updater


# ----------------------------------------------------------
# LuCI controller
# ----------------------------------------------------------

cat > files/usr/lib/lua/luci/controller/doornet2_update.lua <<'EOF'
module("luci.controller.doornet2_update", package.seeall)

function index()

    if not nixio.fs.access(
        "/usr/bin/doornet2-updater"
    ) then
        return
    end

    local page = entry(
        {
            "admin",
            "system",
            "doornet2_update"
        },
        template("doornet2/update"),
        _("DoorNet2 在线升级"),
        90
    )

    page.dependent = false

    entry(
        {
            "admin",
            "system",
            "doornet2_update",
            "status"
        },
        call("action_status")
    ).leaf = true

    entry(
        {
            "admin",
            "system",
            "doornet2_update",
            "check"
        },
        call("action_check")
    ).leaf = true

    entry(
        {
            "admin",
            "system",
            "doornet2_update",
            "prepare"
        },
        call("action_prepare")
    ).leaf = true

    entry(
        {
            "admin",
            "system",
            "doornet2_update",
            "upgrade"
        },
        call("action_upgrade")
    ).leaf = true
end


local function output_json(command)

    local http = require "luci.http"
    local sys = require "luci.sys"

    local result = sys.exec(
        "/usr/bin/doornet2-updater " ..
        command ..
        " 2>/dev/null"
    )

    http.prepare_content(
        "application/json"
    )

    http.write(result)
end


local function require_post()

    local http = require "luci.http"

    if http.getenv(
        "REQUEST_METHOD"
    ) ~= "POST" then

        http.status(
            405,
            "Method Not Allowed"
        )

        http.prepare_content(
            "application/json"
        )

        http.write(
            '{"ok":false,"message":"POST required"}'
        )

        return false
    end

    return true
end


function action_status()
    output_json("status")
end

function action_check()
    output_json("check")
end

function action_prepare()

    if not require_post() then
        return
    end

    output_json("prepare")
end

function action_upgrade()

    if not require_post() then
        return
    end

    output_json("upgrade")
end
EOF


# ----------------------------------------------------------
# LuCI page
# ----------------------------------------------------------

cat > files/usr/lib/lua/luci/view/doornet2/update.htm <<'EOF'
<%+header%>

<h2><%:DoorNet2 在线升级%></h2>

<div class="cbi-map">

    <div class="cbi-section">

        <h3><%:固件信息%></h3>

        <table class="table">

            <tr class="tr">
                <td class="td">
                    <strong>当前版本</strong>
                </td>
                <td class="td" id="current_version">
                    正在读取...
                </td>
            </tr>

            <tr class="tr">
                <td class="td">
                    <strong>最新版本</strong>
                </td>
                <td class="td" id="latest_version">
                    尚未检查
                </td>
            </tr>

            <tr class="tr">
                <td class="td">
                    <strong>当前启动介质</strong>
                </td>
                <td class="td" id="boot_media">
                    -
                </td>
            </tr>

            <tr class="tr">
                <td class="td">
                    <strong>物理类型</strong>
                </td>
                <td class="td" id="media_type">
                    -
                </td>
            </tr>

            <tr class="tr">
                <td class="td">
                    <strong>升级目标磁盘</strong>
                </td>
                <td class="td" id="upgrade_disk">
                    -
                </td>
            </tr>

            <tr class="tr">
                <td class="td">
                    <strong>MMC 固定编号</strong>
                </td>
                <td class="td" id="mmc_layout">
                    -
                </td>
            </tr>

        </table>

    </div>


    <div class="cbi-section">

        <h3><%:在线升级%></h3>

        <p>
            TF：Linux /dev/mmcblk0<br />
            eMMC：Linux /dev/mmcblk1
        </p>

        <p>
            正式升级前会同时检查：
            MMC 控制器、SD/MMC 物理类型、
            当前根设备以及 sysupgrade 实际目标盘。
        </p>


        <div style="margin-top:20px">

            <input
                type="button"
                class="btn cbi-button cbi-button-action"
                id="btn_check"
                value="检查更新"
                onclick="checkUpdate()"
            />

            &nbsp;

            <input
                type="button"
                class="btn cbi-button cbi-button-apply"
                id="btn_prepare"
                value="下载并校验"
                onclick="prepareUpdate()"
                disabled="disabled"
            />

            &nbsp;

            <input
                type="button"
                class="btn cbi-button cbi-button-negative"
                id="btn_upgrade"
                value="立即升级"
                onclick="startUpgrade()"
                disabled="disabled"
            />

        </div>


        <div
            id="status_box"
            style="
                margin-top:20px;
                padding:15px;
                border:1px solid #ccc;
                border-radius:4px;
                min-height:24px;
            "
        >
            正在读取设备状态...
        </div>

    </div>

</div>


<script type="text/javascript">

var BASE =
    '<%=luci.dispatcher.build_url(
        "admin",
        "system",
        "doornet2_update"
    )%>';


function setStatus(text)
{
    document.getElementById(
        "status_box"
    ).innerHTML = text;
}


function request(path, method, callback)
{
    var xhr = new XMLHttpRequest();

    xhr.open(
        method,
        BASE + "/" + path,
        true
    );

    if (method == "POST")
    {
        xhr.setRequestHeader(
            "Content-Type",
            "application/x-www-form-urlencoded"
        );
    }

    xhr.onreadystatechange =
        function()
        {
            if (xhr.readyState != 4)
                return;

            var data;

            try
            {
                data =
                    JSON.parse(
                        xhr.responseText
                    );
            }
            catch (e)
            {
                callback(
                    {
                        ok: false,
                        message:
                            "返回数据解析失败"
                    }
                );

                return;
            }

            callback(data);
        };

    xhr.send(
        method == "POST"
            ? "confirm=1"
            : null
    );
}


function showDevice(data)
{
    if (data.current_version)
        document.getElementById(
            "current_version"
        ).innerHTML =
            data.current_version;

    if (data.boot_media)
        document.getElementById(
            "boot_media"
        ).innerHTML =
            data.boot_media;

    if (data.media_type)
        document.getElementById(
            "media_type"
        ).innerHTML =
            data.media_type;

    if (data.upgrade_disk)
        document.getElementById(
            "upgrade_disk"
        ).innerHTML =
            data.upgrade_disk;

    if (data.mmc_layout)
        document.getElementById(
            "mmc_layout"
        ).innerHTML =
            data.mmc_layout;
}


function loadStatus()
{
    request(
        "status",
        "GET",
        function(data)
        {
            if (!data.ok)
            {
                setStatus(
                    "读取状态失败"
                );

                return;
            }

            showDevice(data);

            setStatus(
                "设备状态已读取。"
            );
        }
    );
}


function checkUpdate()
{
    setStatus(
        "正在检查更新..."
    );

    request(
        "check",
        "GET",
        function(data)
        {
            if (!data.ok)
            {
                setStatus(
                    "<strong>检查失败：</strong> "
                    +
                    (
                        data.message ||
                        "未知错误"
                    )
                );

                return;
            }

            showDevice(data);

            document.getElementById(
                "latest_version"
            ).innerHTML =
                data.latest_version;

            if (data.update_available)
            {
                document.getElementById(
                    "btn_prepare"
                ).disabled = false;

                setStatus(
                    "<strong>发现新版本。</strong>"
                    +
                    "<br />MMC 固定编号：通过"
                );
            }
            else
            {
                setStatus(
                    "<strong>当前已经是最新版本。</strong>"
                );
            }
        }
    );
}


function prepareUpdate()
{
    if (!confirm(
        "下载固件并执行全部安全校验？"
    ))
        return;

    document.getElementById(
        "btn_prepare"
    ).disabled = true;

    setStatus(
        "正在下载、校验 SHA256、sysupgrade 和物理目标盘..."
    );

    request(
        "prepare",
        "POST",
        function(data)
        {
            if (!data.ok)
            {
                setStatus(
                    "<strong>准备失败：</strong> "
                    +
                    (
                        data.message ||
                        "未知错误"
                    )
                    +
                    (
                        data.guard_message
                        ? "<br />保险锁：" +
                          data.guard_message
                        : ""
                    )
                );

                return;
            }

            showDevice(data);

            document.getElementById(
                "btn_upgrade"
            ).disabled = false;

            setStatus(
                "<strong>固件准备完成。</strong>"
                +
                "<br />SHA256：通过"
                +
                "<br />sysupgrade：通过"
                +
                "<br />MMC 固定编号：通过"
                +
                "<br />物理介质：" +
                data.media_type
                +
                "<br />DoorNet2 目标：" +
                data.upgrade_disk
                +
                "<br />sysupgrade 目标：" +
                data.sysupgrade_disk
                +
                "<br />目标保险锁：通过"
                +
                "<br />当前配置：默认保留"
            );
        }
    );
}


function startUpgrade()
{
    if (!confirm(
        "正式开始升级？\n\n" +
        "系统会在写盘前再次执行最终目标盘保护检查。\n\n" +
        "当前配置会默认保留（PassWall / PassWall2 / SmartDNS / AdGuard Home / dnsmasq 等）。\n\n" +
        "升级期间不要断电。"
    ))
        return;

    setStatus(
        "正在执行最终保险检查..."
    );

    request(
        "upgrade",
        "POST",
        function(data)
        {
            if (!data.ok)
            {
                setStatus(
                    "<strong>拒绝升级：</strong> "
                    +
                    (
                        data.message ||
                        "未知错误"
                    )
                    +
                    (
                        data.guard_message
                        ? "<br />保险锁：" +
                          data.guard_message
                        : ""
                    )
                );

                return;
            }

            setStatus(
                "<strong>升级已启动。</strong>"
                +
                "<br />目标：" +
                data.upgrade_disk
                +
                "<br />sysupgrade：" +
                data.sysupgrade_disk
                +
                "<br />保险锁：通过"
                +
                "<br />当前配置：已按保留模式升级"
                +
                "<br /><br />设备即将自动重启。"
            );
        }
    );
}


window.onload = loadStatus;

</script>

<%+footer%>
EOF
