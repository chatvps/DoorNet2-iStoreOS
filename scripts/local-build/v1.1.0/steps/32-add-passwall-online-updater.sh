#!/usr/bin/env bash
# Migrated from V1.7 workflow step 32: Add PassWall online updater
set -e

mkdir -p \
  files/usr/bin \
  files/usr/lib/lua/luci/controller \
  files/usr/lib/lua/luci/view/doornet2

cat > files/usr/bin/doornet2-passwall-updater <<'EOF'
#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

FILTER='^(luci-app-passwall|luci-i18n-passwall-|chinadns-ng|dns2socks|haproxy|hysteria|ipt2socks|microsocks|naiveproxy|shadow-tls|simple-obfs|tcping|v2ray-geoip|v2ray-geosite|xray-core|xray-plugin)$'

json_escape()
{
    printf '%s' "$1" \
      | sed \
          -e 's/\\/\\\\/g' \
          -e 's/"/\\"/g' \
          -e ':a;N;$!ba;s/\n/\\n/g'
}

installed_version()
{
    opkg status luci-app-passwall 2>/dev/null \
      | awk -F': ' '$1 == "Version" { print $2; exit }'
}

available_version()
{
    opkg list luci-app-passwall 2>/dev/null \
      | awk '$1 == "luci-app-passwall" { print $3; exit }'
}

upgradable_packages()
{
    opkg list-upgradable 2>/dev/null \
      | awk '{ print $1 }' \
      | grep -E "$FILTER" \
      || true
}

status_json()
{
    local installed available packages count

    installed="$(installed_version)"
    available="$(available_version)"
    packages="$(upgradable_packages)"
    count="$(printf '%s\n' "$packages" | sed '/^$/d' | wc -l)"

    printf '{'
    printf '"installed":"%s",' "$(json_escape "${installed:-not-installed}")"
    printf '"available":"%s",' "$(json_escape "${available:-unknown}")"
    printf '"count":%s,' "${count:-0}"
    printf '"packages":"%s"' "$(json_escape "$packages")"
    printf '}\n'
}

do_check()
{
    opkg update >/tmp/passwall-opkg-update.log 2>&1 || {
        printf '{"ok":false,"message":"OPKG 更新失败，请查看 /tmp/passwall-opkg-update.log"}\n'
        return 1
    }

    printf '{"ok":true,"status":'
    status_json | tr -d '\n'
    printf '}\n'
}

do_upgrade()
{
    local packages

    opkg update >/tmp/passwall-opkg-update.log 2>&1 || {
        printf '{"ok":false,"message":"OPKG 更新失败"}\n'
        return 1
    }

    packages="$(upgradable_packages)"

    if [ -z "$packages" ]; then
        printf '{"ok":true,"message":"PassWall 已经是最新版本，没有需要更新的组件。"}\n'
        return 0
    fi

    echo "$packages" > /tmp/passwall-upgrade-packages.txt

    # shellcheck disable=SC2086
    if opkg upgrade $packages >/tmp/passwall-upgrade.log 2>&1; then
        rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
        /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
        printf '{"ok":true,"message":"PassWall 在线更新完成。建议刷新浏览器；如核心正在运行，可重启 PassWall 服务。"}\n'
    else
        printf '{"ok":false,"message":"PassWall 更新失败，请查看 /tmp/passwall-upgrade.log"}\n'
        return 1
    fi
}

case "$1" in
    status)
        status_json
        ;;
    check)
        do_check
        ;;
    upgrade)
        do_upgrade
        ;;
    *)
        echo "Usage: doornet2-passwall-updater {status|check|upgrade}" >&2
        exit 1
        ;;
esac
EOF

chmod 755 files/usr/bin/doornet2-passwall-updater
sh -n files/usr/bin/doornet2-passwall-updater

cat > files/usr/lib/lua/luci/controller/doornet2_passwall_update.lua <<'EOF'
module("luci.controller.doornet2_passwall_update", package.seeall)

function index()
    if not nixio.fs.access("/usr/bin/doornet2-passwall-updater") then
        return
    end

    local page = entry(
        {"admin", "services", "doornet2_passwall_update"},
        template("doornet2/passwall_update"),
        _("PassWall 在线升级"),
        99
    )
    page.dependent = false

    entry(
        {"admin", "services", "doornet2_passwall_update", "status"},
        call("action_status")
    ).leaf = true

    entry(
        {"admin", "services", "doornet2_passwall_update", "check"},
        call("action_check")
    ).leaf = true

    entry(
        {"admin", "services", "doornet2_passwall_update", "upgrade"},
        call("action_upgrade")
    ).leaf = true
end

local function output(command)
    local http = require "luci.http"
    local sys = require "luci.sys"
    http.prepare_content("application/json")
    http.write(sys.exec("/usr/bin/doornet2-passwall-updater " .. command .. " 2>/dev/null"))
end

function action_status()
    output("status")
end

function action_check()
    output("check")
end

function action_upgrade()
    output("upgrade")
end
EOF

cat > files/usr/lib/lua/luci/view/doornet2/passwall_update.htm <<'EOF'
<%+header%>

<h2><%:PassWall 在线升级%></h2>

<div class="cbi-map-descr">
  <%:只更新 PassWall、中文包以及 PassWall 使用的用户态核心组件。不会更新内核、kmod，也不会刷写 DoorNet2 固件。更新包来自 DoorNet2 自己的 GitHub OPKG feed，与当前固件使用同一套源码和编译环境。%>
</div>

<div class="cbi-section">
  <div class="cbi-section-node">
    <p><strong><%:已安装版本%>：</strong><span id="pw-installed">读取中...</span></p>
    <p><strong><%:Feed 版本%>：</strong><span id="pw-available">读取中...</span></p>
    <p><strong><%:可更新组件%>：</strong><span id="pw-count">-</span></p>
    <pre id="pw-packages" style="white-space:pre-wrap;min-height:40px"></pre>

    <p>
      <button class="cbi-button cbi-button-action" type="button" onclick="pwCheck()"><%:检查更新%></button>
      <button class="cbi-button cbi-button-apply" type="button" onclick="pwUpgrade()"><%:立即更新%></button>
    </p>

    <div id="pw-message"></div>
  </div>
</div>

<script type="text/javascript">
function setMsg(s) {
    document.getElementById('pw-message').innerHTML = s || '';
}

function renderStatus(s) {
    if (!s) return;
    document.getElementById('pw-installed').textContent = s.installed || 'unknown';
    document.getElementById('pw-available').textContent = s.available || 'unknown';
    document.getElementById('pw-count').textContent = s.count || 0;
    document.getElementById('pw-packages').textContent = s.packages || '没有可更新组件';
}

function req(path, cb) {
    XHR.get('<%=luci.dispatcher.build_url("admin/services/doornet2_passwall_update")%>/' + path, null, function(x, data) {
        cb(data || {});
    });
}

function pwStatus() {
    req('status', function(data) { renderStatus(data); });
}

function pwCheck() {
    setMsg('正在更新软件列表并检查 PassWall...');
    req('check', function(data) {
        if (data.ok && data.status) {
            renderStatus(data.status);
            setMsg('<strong>检查完成。</strong>');
        } else {
            setMsg('<strong>检查失败：</strong>' + (data.message || 'unknown'));
        }
    });
}

function pwUpgrade() {
    if (!confirm('确认在线更新 PassWall 及其用户态核心组件？')) return;
    setMsg('正在更新，请不要关闭页面或断电...');
    req('upgrade', function(data) {
        setMsg('<strong>' + (data.message || (data.ok ? '完成' : '失败')) + '</strong>');
        setTimeout(pwStatus, 2500);
    });
}

window.onload = pwStatus;
</script>

<%+footer%>
EOF

echo "===== PASSWALL ONLINE UPDATER ====="
sh -n files/usr/bin/doornet2-passwall-updater
grep -nE \
  'PassWall 在线升级|doornet2-passwall-updater' \
  files/usr/lib/lua/luci/controller/doornet2_passwall_update.lua
