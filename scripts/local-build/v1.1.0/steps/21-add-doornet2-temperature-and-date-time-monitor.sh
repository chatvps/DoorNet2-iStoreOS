#!/usr/bin/env bash
# Migrated from V1.7 workflow step 21: Add DoorNet2 temperature and date time monitor
set -e

echo "===== ADD DOORNET2 R34 THEME-INDEPENDENT RUNTIME MONITOR ====="

mkdir -p \
  files/usr/bin \
  files/usr/lib/lua/luci/controller \
  files/www/luci-static/doornet2 \
  files/etc/uci-defaults

cat > files/usr/bin/doornet2-runtime-status <<'EOF'
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

format_temp()
{
    local raw whole decimal
    raw="$1"

    case "$raw" in
        ''|*[!0-9-]*)
            return 1
            ;;
    esac

    if [ "$raw" -gt 1000 ] 2>/dev/null; then
        whole=$((raw / 1000))
        decimal=$(((raw % 1000) / 100))
        printf '%s.%s' "$whole" "$decimal"
    else
        printf '%s.0' "$raw"
    fi
}

cpu_temp=''
cpu_type=''
fallback_temp=''
fallback_type=''

for zone in /sys/class/thermal/thermal_zone*; do
    [ -d "$zone" ] || continue
    [ -r "$zone/temp" ] || continue

    raw="$(cat "$zone/temp" 2>/dev/null || true)"
    value="$(format_temp "$raw" 2>/dev/null || true)"
    [ -n "$value" ] || continue

    type="$(cat "$zone/type" 2>/dev/null || echo thermal)"

    if [ -z "$fallback_temp" ]; then
        fallback_temp="$value"
        fallback_type="$type"
    fi

    case "$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')" in
        *cpu*|*soc*|*package*)
            if [ -z "$cpu_temp" ]; then
                cpu_temp="$value"
                cpu_type="$type"
            fi
            ;;
    esac
done

if [ -z "$cpu_temp" ]; then
    cpu_temp="$fallback_temp"
    cpu_type="$fallback_type"
fi

now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
timezone="$(date '+%Z' 2>/dev/null || true)"

if [ -z "$cpu_temp" ]; then
    cpu_temp='--'
    cpu_type='unavailable'
fi

printf '{'
printf '"ok":true,'
printf '"temperature":"%s",' "$(json_escape "$cpu_temp")"
printf '"thermal_type":"%s",' "$(json_escape "$cpu_type")"
printf '"datetime":"%s",' "$(json_escape "$now")"
printf '"timezone":"%s"' "$(json_escape "$timezone")"
printf '}\n'
EOF

chmod 755 files/usr/bin/doornet2-runtime-status
sh -n files/usr/bin/doornet2-runtime-status

cat > files/usr/lib/lua/luci/controller/doornet2_runtime.lua <<'EOF'
module("luci.controller.doornet2_runtime", package.seeall)

function index()
    local page = entry(
        {"admin", "status", "doornet2_runtime"},
        call("action_status")
    )
    page.leaf = true
end

function action_status()
    local http = require "luci.http"
    local sys = require "luci.sys"

    http.prepare_content("application/json")
    http.header("Cache-Control", "no-store")
    http.write(sys.exec("/usr/bin/doornet2-runtime-status 2>/dev/null"))
end
EOF

cat > files/www/luci-static/doornet2/runtime-monitor.js <<'EOF'
(function() {
  'use strict';

  if (window.location.pathname.indexOf('/admin/') < 0)
    return;

  function makeMonitor() {
    var old = document.getElementById('dn-runtime-monitor');
    if (old) return old;

    var box = document.createElement('div');
    box.id = 'dn-runtime-monitor';
    box.setAttribute('title', 'DoorNet2 RK3399 运行状态');
    box.innerHTML =
      '<span class="dn-runtime-dot"></span>' +
      '<span class="dn-runtime-temp">CPU --°C</span>' +
      '<span class="dn-runtime-sep">·</span>' +
      '<span class="dn-runtime-time">---- -- -- --:--:--</span>';

    document.body.appendChild(box);
    return box;
  }

  function setLevel(box, value) {
    box.classList.remove('dn-temp-normal', 'dn-temp-warm', 'dn-temp-hot');
    var n = parseFloat(value);
    if (isNaN(n)) return;
    if (n >= 80) box.classList.add('dn-temp-hot');
    else if (n >= 70) box.classList.add('dn-temp-warm');
    else box.classList.add('dn-temp-normal');
  }

  function update() {
    var box = makeMonitor();

    fetch('/cgi-bin/luci/admin/status/doornet2_runtime', {
      method: 'GET',
      credentials: 'same-origin',
      cache: 'no-store'
    })
    .then(function(r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    })
    .then(function(data) {
      if (!data || !data.ok) throw new Error('invalid status');

      var temp = data.temperature || '--';
      var time = data.datetime || '---- -- -- --:--:--';
      var tz = data.timezone || '';

      box.querySelector('.dn-runtime-temp').textContent = 'CPU ' + temp + '°C';
      box.querySelector('.dn-runtime-time').textContent = time + (tz ? ' ' + tz : '');
      setLevel(box, temp);
      box.classList.remove('dn-runtime-offline');
    })
    .catch(function() {
      box.classList.add('dn-runtime-offline');
    });
  }

  function start() {
    makeMonitor();
    update();
    window.setInterval(update, 5000);
  }

  if (document.readyState === 'loading')
    document.addEventListener('DOMContentLoaded', start);
  else
    start();
})();
EOF

cat > files/www/luci-static/doornet2/runtime-monitor.css <<'EOF'
#dn-runtime-monitor {
  position: fixed;
  top: 10px;
  right: 76px;
  z-index: 10020;
  display: flex;
  align-items: center;
  gap: 6px;
  min-height: 26px;
  padding: 0 9px;
  border: 1px solid rgba(127,127,127,.24);
  border-radius: 7px;
  background: rgba(30,30,30,.88);
  color: #f3f4f6;
  box-shadow: 0 1px 4px rgba(0,0,0,.18);
  font-size: 11px;
  line-height: 1;
  white-space: nowrap;
  pointer-events: none;
  backdrop-filter: blur(6px);
}

#dn-runtime-monitor .dn-runtime-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #62d394;
}

#dn-runtime-monitor.dn-temp-warm .dn-runtime-dot {
  background: #f0b35a;
}

#dn-runtime-monitor.dn-temp-hot .dn-runtime-dot {
  background: #ff6b6b;
}

#dn-runtime-monitor.dn-runtime-offline {
  opacity: .55;
}

#dn-runtime-monitor .dn-runtime-sep {
  opacity: .45;
}

@media (max-width: 900px) {
  #dn-runtime-monitor {
    top: auto;
    right: 10px;
    bottom: 58px;
    max-width: calc(100vw - 20px);
  }
}
EOF

python3 - <<'PY2'
from pathlib import Path

headers = [
    Path('package/lean/luci-theme-design/luasrc/view/themes/design/header.htm'),
    Path('package/lean/luci-theme-argon/luasrc/view/themes/argon/header.htm'),
]

css = '<link rel="stylesheet" href="/luci-static/doornet2/runtime-monitor.css">'
js = '<script defer src="/luci-static/doornet2/runtime-monitor.js"></script>'

patched = 0

for p in headers:
    if not p.exists():
        continue

    text = p.read_text(errors='ignore')
    old = text

    inject = []
    if css not in text:
        inject.append(css)
    if js not in text:
        inject.append(js)

    if inject:
        if '</head>' not in text:
            raise SystemExit('ERROR: theme header has no </head>: %s' % p)
        text = text.replace(
            '</head>',
            '\n'.join('\t' + x for x in inject) + '\n</head>',
            1
        )

    if text != old:
        p.write_text(text)
        patched += 1
        print('patched runtime monitor header:', p)

design = Path('package/lean/luci-theme-design/luasrc/view/themes/design/header.htm')
final = design.read_text(errors='ignore')

if css not in final or js not in final:
    raise SystemExit('ERROR: Design header monitor injection failed')

print('runtime monitor source headers patched:', patched)
PY2

cat > files/etc/uci-defaults/99-doornet2-runtime-header-fix <<'EOF'
#!/bin/sh

CSS='<link rel="stylesheet" href="/luci-static/doornet2/runtime-monitor.css">'
JS='<script defer src="/luci-static/doornet2/runtime-monitor.js"></script>'

patch_header()
{
    local hdr="$1"
    [ -f "$hdr" ] || return 0

    # Design/Argon packages may install a fresh header after the
    # source-tree patch step. Patch the ACTUAL installed file here.
    if ! grep -q 'runtime-monitor.css' "$hdr"; then
        sed -i "\|</head>|i\\$CSS" "$hdr"
    fi

    if ! grep -q 'runtime-monitor.js' "$hdr"; then
        sed -i "\|</head>|i\\$JS" "$hdr"
    fi
}

DESIGN_HDR="/usr/lib/lua/luci/view/themes/design/header.htm"
ARGON_HDR="/usr/lib/lua/luci/view/themes/argon/header.htm"

patch_header "$DESIGN_HDR"
patch_header "$ARGON_HDR"

# Make the Design theme's home shortcut open QuickStart on the
# actually installed header too. This is intentionally idempotent.
if [ -f "$DESIGN_HDR" ]; then
    sed -i \
      's#/cgi-bin/luci/admin/status/overview#/cgi-bin/luci/admin/quickstart/#g' \
      "$DESIGN_HDR"
fi

rm -rf \
  /tmp/luci-indexcache \
  /tmp/luci-modulecache \
  /tmp/luci-templatecache

exit 0
EOF

chmod 755 files/etc/uci-defaults/99-doornet2-runtime-header-fix
sh -n files/etc/uci-defaults/99-doornet2-runtime-header-fix

cat > files/etc/uci-defaults/98-doornet2-time <<'EOF'
#!/bin/sh

uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.@system[0].timezone='CST-8'

if ! uci -q get system.ntp >/dev/null 2>&1; then
    uci -q set system.ntp='timeserver'
fi

uci -q set system.ntp.enabled='1'
uci -q delete system.ntp.server
uci -q add_list system.ntp.server='ntp.aliyun.com'
uci -q add_list system.ntp.server='ntp.tencent.com'
uci -q add_list system.ntp.server='0.openwrt.pool.ntp.org'
uci -q add_list system.ntp.server='1.openwrt.pool.ntp.org'
uci -q commit system

if [ -x /etc/init.d/sysntpd ]; then
    /etc/init.d/sysntpd enable >/dev/null 2>&1 || true
    /etc/init.d/sysntpd restart >/dev/null 2>&1 || true
fi

rm -rf \
  /tmp/luci-indexcache \
  /tmp/luci-modulecache \
  /tmp/luci-templatecache

exit 0
EOF

chmod 755 files/etc/uci-defaults/98-doornet2-time
sh -n files/etc/uci-defaults/98-doornet2-time

echo "===== R34 RUNTIME MONITOR FILES ====="
test -x files/usr/bin/doornet2-runtime-status
test -s files/usr/lib/lua/luci/controller/doornet2_runtime.lua
test -s files/www/luci-static/doornet2/runtime-monitor.js
test -s files/www/luci-static/doornet2/runtime-monitor.css
test -x files/etc/uci-defaults/98-doornet2-time
test -x files/etc/uci-defaults/99-doornet2-runtime-header-fix
grep -q 'runtime-monitor.css' \
  package/lean/luci-theme-design/luasrc/view/themes/design/header.htm
grep -q 'runtime-monitor.js' \
  package/lean/luci-theme-design/luasrc/view/themes/design/header.htm
