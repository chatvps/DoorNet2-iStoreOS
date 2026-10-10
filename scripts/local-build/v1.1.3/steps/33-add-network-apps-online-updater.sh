#!/usr/bin/env bash
# Migrated from V1.7 workflow step 33: Add network apps online updater
set -e

mkdir -p \
  files/usr/bin \
  files/usr/lib/lua/luci/controller \
  files/usr/lib/lua/luci/view/doornet2

cat > files/usr/bin/doornet2-app-updater <<'EOF'
#!/bin/sh

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

json_escape()
{
    printf '%s' "$1" \
      | sed \
          -e 's/\\/\\\\/g' \
          -e 's/"/\\"/g' \
          -e ':a;N;$!ba;s/\n/\\n/g'
}

component_meta()
{
    case "$1" in
        passwall)
            LABEL='PassWall 代理分流'
            MAIN='luci-app-passwall'
            SERVICE='passwall'
            FILTER='^(luci-app-passwall|luci-i18n-passwall-|chinadns-ng|dns2socks|haproxy|hysteria|ipt2socks|microsocks|naiveproxy|shadow-tls|simple-obfs|tcping|v2ray-geoip|v2ray-geosite|xray-core|xray-plugin)$'
            ;;
        smartdns)
            LABEL='SmartDNS DNS 加速'
            MAIN='smartdns'
            SERVICE='smartdns'
            FILTER='^(smartdns|smartdns-ui|luci-app-smartdns|luci-i18n-smartdns-.*)$'
            ;;
        passwall2)
            LABEL='PassWall2 代理分流'
            MAIN='luci-app-passwall2'
            SERVICE='passwall2'
            FILTER='^(luci-app-passwall2|luci-i18n-passwall2-.*|chinadns-ng|dnsmasq-full|haproxy|simple-obfs|tcping|v2ray-geoip|v2ray-geosite|xray-core)$'
            ;;
        adguard)
            LABEL='AdGuard Home'
            MAIN='adguardhome'
            SERVICE='adguardhome'
            FILTER='^(adguardhome|luci-app-adguardhome|luci-i18n-adguardhome-.*)$'
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

installed_version()
{
    opkg status "$MAIN" 2>/dev/null \
      | awk -F': ' '$1 == "Version" { print $2; exit }'
}

available_version()
{
    opkg list "$MAIN" 2>/dev/null \
      | awk -v p="$MAIN" '$1 == p { print $3; exit }'
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
    local component installed available packages count

    component="$1"

    component_meta "$component" || {
        printf '{"ok":false,"message":"unknown component"}\n'
        return 1
    }

    installed="$(installed_version)"
    available="$(available_version)"
    packages="$(upgradable_packages)"
    count="$(printf '%s\n' "$packages" | sed '/^$/d' | wc -l)"

    printf '{'
    printf '"ok":true,'
    printf '"component":"%s",' "$(json_escape "$component")"
    printf '"label":"%s",' "$(json_escape "$LABEL")"
    printf '"installed":"%s",' "$(json_escape "${installed:-not-installed}")"
    printf '"available":"%s",' "$(json_escape "${available:-unknown}")"
    printf '"count":%s,' "${count:-0}"
    printf '"packages":"%s"' "$(json_escape "$packages")"
    printf '}\n'
}

do_refresh()
{
    if opkg update >/tmp/doornet2-app-opkg-update.log 2>&1; then
        printf '{"ok":true,"message":"软件列表更新完成"}\n'
    else
        printf '{"ok":false,"message":"OPKG 更新失败，请查看 /tmp/doornet2-app-opkg-update.log"}\n'
        return 1
    fi
}

do_upgrade()
{
    local component packages was_enabled

    component="$1"

    component_meta "$component" || {
        printf '{"ok":false,"message":"unknown component"}\n'
        return 1
    }

    opkg update >/tmp/doornet2-app-opkg-update.log 2>&1 || {
        printf '{"ok":false,"message":"OPKG 更新失败"}\n'
        return 1
    }

    packages="$(upgradable_packages)"

    if [ -z "$packages" ]; then
        printf '{"ok":true,"message":"%s 已经是最新版本，没有需要更新的组件。"}\n' \
          "$(json_escape "$LABEL")"
        return 0
    fi

    # The filters above intentionally exclude all kmod/kernel packages.
    echo "$packages" > "/tmp/doornet2-${component}-upgrade-packages.txt"

    was_enabled=0
    if [ -n "$SERVICE" ] && [ -x "/etc/init.d/$SERVICE" ]; then
        "/etc/init.d/$SERVICE" enabled >/dev/null 2>&1 && was_enabled=1 || true
    fi

    # shellcheck disable=SC2086
    if opkg upgrade $packages >"/tmp/doornet2-${component}-upgrade.log" 2>&1; then
        rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

        if [ "$was_enabled" = "1" ] && [ -x "/etc/init.d/$SERVICE" ]; then
            "/etc/init.d/$SERVICE" restart >/dev/null 2>&1 || true
        fi

        /etc/init.d/uhttpd restart >/dev/null 2>&1 || true

        printf '{"ok":true,"message":"%s 在线更新完成。"}\n' \
          "$(json_escape "$LABEL")"
    else
        printf '{"ok":false,"message":"%s 更新失败，请查看 %s"}\n' \
          "$(json_escape "$LABEL")" \
          "$(json_escape "/tmp/doornet2-${component}-upgrade.log")"
        return 1
    fi
}

case "$1" in
    refresh)
        do_refresh
        ;;
    status)
        status_json "$2"
        ;;
    upgrade)
        do_upgrade "$2"
        ;;
    *)
        echo "Usage: doornet2-app-updater {refresh|status COMPONENT|upgrade COMPONENT}" >&2
        exit 1
        ;;
esac
EOF

chmod 755 files/usr/bin/doornet2-app-updater
sh -n files/usr/bin/doornet2-app-updater

cat > files/usr/lib/lua/luci/controller/doornet2_app_update.lua <<'EOF'
module("luci.controller.doornet2_app_update", package.seeall)

local allowed = {
    passwall = true,
    smartdns = true,
    passwall2 = true,
    adguard = true
}

function index()
    if not nixio.fs.access("/usr/bin/doornet2-app-updater") then
        return
    end

    local page = entry(
        {"admin", "services", "doornet2_app_update"},
        template("doornet2/app_update"),
        _("DoorNet2 组件在线升级"),
        98
    )
    page.dependent = false

    entry(
        {"admin", "services", "doornet2_app_update", "refresh"},
        call("action_refresh")
    ).leaf = true

    entry(
        {"admin", "services", "doornet2_app_update", "status"},
        call("action_status")
    ).leaf = true

    entry(
        {"admin", "services", "doornet2_app_update", "upgrade"},
        call("action_upgrade")
    ).leaf = true
end

local function output(command, component)
    local http = require "luci.http"
    local sys = require "luci.sys"

    http.prepare_content("application/json")

    if component and not allowed[component] then
        http.write('{"ok":false,"message":"invalid component"}')
        return
    end

    local cmd = "/usr/bin/doornet2-app-updater " .. command

    if component then
        cmd = cmd .. " " .. component
    end

    http.write(sys.exec(cmd .. " 2>/dev/null"))
end

function action_refresh()
    output("refresh", nil)
end

function action_status()
    local http = require "luci.http"
    output("status", http.formvalue("component"))
end

function action_upgrade()
    local http = require "luci.http"
    output("upgrade", http.formvalue("component"))
end
EOF

cat > files/usr/lib/lua/luci/view/doornet2/app_update.htm <<'EOF'
<%+header%>

<h2><%:DoorNet2 组件在线升级%></h2>

<div class="cbi-map-descr">
  <%:这里仅更新用户态应用包，不更新内核/kmod，也不会刷写固件。软件包来自 DoorNet2 自己的 GitHub OPKG feed，与当前固件使用同一套编译环境。SmartDNS 与 AdGuard Home 都可能提供 DNS 服务，请先规划端口后再启用，避免同时占用 53 端口。%>
</div>

<p>
  <button class="cbi-button cbi-button-action" type="button" onclick="refreshAll()"><%:更新软件列表并检查全部%></button>
</p>

<div id="dn-app-message"></div>

<div class="cbi-section">
  <div class="cbi-section-node">
    <table class="table">
      <tr class="tr table-titles">
        <th class="th"><%:组件%></th>
        <th class="th"><%:当前版本%></th>
        <th class="th"><%:Feed版本%></th>
        <th class="th"><%:可更新包%></th>
        <th class="th"><%:操作%></th>
      </tr>
      <tbody id="dn-app-body"></tbody>
    </table>
  </div>
</div>

<script type="text/javascript">
var components = [
    ['passwall', 'PassWall 代理分流'],
    ['smartdns', 'SmartDNS DNS 加速'],
    ['passwall2', 'PassWall2 代理分流'],
    ['adguard', 'AdGuard Home']
];

function esc(s) {
    return String(s == null ? '' : s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function rowHtml(c, label) {
    return '<tr class="tr" id="row-' + c + '">' +
        '<td class="td"><strong>' + esc(label) + '</strong></td>' +
        '<td class="td" id="installed-' + c + '">读取中...</td>' +
        '<td class="td" id="available-' + c + '">读取中...</td>' +
        '<td class="td"><span id="count-' + c + '">-</span><pre id="packages-' + c + '" style="white-space:pre-wrap;margin:6px 0 0"></pre></td>' +
        '<td class="td"><button class="cbi-button cbi-button-apply" type="button" onclick="upgradeOne(\'' + c + '\',\'' + esc(label) + '\')">在线更新</button></td>' +
        '</tr>';
}

function initRows() {
    var html = '';
    for (var i = 0; i < components.length; i++) {
        html += rowHtml(components[i][0], components[i][1]);
    }
    document.getElementById('dn-app-body').innerHTML = html;
}

function setMsg(s) {
    document.getElementById('dn-app-message').innerHTML = s || '';
}

function statusOne(c) {
    XHR.get(
        '<%=luci.dispatcher.build_url("admin/services/doornet2_app_update/status")%>',
        { component: c },
        function(x, data) {
            data = data || {};
            document.getElementById('installed-' + c).textContent = data.installed || 'unknown';
            document.getElementById('available-' + c).textContent = data.available || 'unknown';
            document.getElementById('count-' + c).textContent = data.count || 0;
            document.getElementById('packages-' + c).textContent = data.packages || '';
        }
    );
}

function statusAll() {
    for (var i = 0; i < components.length; i++) {
        statusOne(components[i][0]);
    }
}

function refreshAll() {
    setMsg('<strong>正在更新软件列表...</strong>');
    XHR.get(
        '<%=luci.dispatcher.build_url("admin/services/doornet2_app_update/refresh")%>',
        null,
        function(x, data) {
            data = data || {};
            setMsg('<strong>' + esc(data.message || (data.ok ? '检查完成' : '检查失败')) + '</strong>');
            statusAll();
        }
    );
}

function upgradeOne(c, label) {
    if (!confirm('确认在线更新 ' + label + '？')) return;

    setMsg('<strong>正在更新 ' + esc(label) + '，请不要断电...</strong>');

    XHR.get(
        '<%=luci.dispatcher.build_url("admin/services/doornet2_app_update/upgrade")%>',
        { component: c },
        function(x, data) {
            data = data || {};
            setMsg('<strong>' + esc(data.message || (data.ok ? '完成' : '失败')) + '</strong>');
            setTimeout(function() { statusOne(c); }, 2500);
        }
    );
}

initRows();
statusAll();
</script>

<%+footer%>
EOF

echo "===== NETWORK APPS ONLINE UPDATER ====="
sh -n files/usr/bin/doornet2-app-updater
grep -nE \
  'DoorNet2 组件在线升级|doornet2-app-updater' \
  files/usr/lib/lua/luci/controller/doornet2_app_update.lua
