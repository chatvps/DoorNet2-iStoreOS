#!/bin/bash

set -e

cd ~/DoorNet2-iStoreOS

echo "===== DoorNet2 UI 创建 ====="

# -------------------------
# 目录
# -------------------------

mkdir -p files/usr/lib/lua/luci/view/doornet2_status
mkdir -p files/usr/lib/lua/luci/view/doornet2_shunt
mkdir -p files/usr/lib/lua/luci/controller
mkdir -p files/etc/doornet2


# -------------------------
# 版本文件
# -------------------------

cat > files/etc/doornet2/version.json <<'EOT'
{
 "device":"DoorNet2",
 "version":"2026.10.04-r5251",
 "build":"iStoreOS",
 "target":"embedfire_doornet2"
}
EOT


# -------------------------
# 状态控制器
# -------------------------

cat > files/usr/lib/lua/luci/controller/doornet2_status.lua <<'EOT'
module("luci.controller.doornet2_status", package.seeall)

function index()

entry(
 {"admin","status","doornet2"},
 template("doornet2_status/main"),
 _("DoorNet2状态"),
 20
)

end
EOT


# -------------------------
# 状态页面
# -------------------------

cat > files/usr/lib/lua/luci/view/doornet2_status/main.htm <<'EOT'
<%+header%>

<h2>DoorNet2 状态</h2>

<table class="table">
<tr>
<td>设备</td>
<td>DoorNet2</td>
</tr>

<tr>
<td>CPU</td>
<td><%=luci.sys.exec("cat /proc/cpuinfo | grep Hardware | head -1")%></td>
</tr>

<tr>
<td>温度</td>
<td><%=luci.sys.exec("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000\" ℃\"}'")%></td>
</tr>


<tr>
<td>内存</td>
<td><%=luci.sys.exec("free -m | grep Mem")%></td>
</tr>

<tr>
<td>PassWall</td>
<td><%=luci.sys.exec("/etc/init.d/passwall enabled >/dev/null && echo 已启用 || echo 未启用")%></td>
</tr>


<tr>
<td>SmartDNS</td>
<td><%=luci.sys.exec("/etc/init.d/smartdns enabled >/dev/null && echo 已启用 || echo 未启用")%></td>
</tr>


<tr>
<td>AdGuard Home</td>
<td><%=luci.sys.exec("/etc/init.d/adguardhome enabled >/dev/null && echo 已启用 || echo 未启用")%></td>
</tr>

</table>

<%+footer%>
EOT



# -------------------------
# 分流控制器
# -------------------------

cat > files/usr/lib/lua/luci/controller/doornet2_shunt.lua <<'EOT'
module("luci.controller.doornet2_shunt", package.seeall)

function index()

entry(
 {"admin","services","doornet2_shunt"},
 template("doornet2_shunt/main"),
 _("分流总节点"),
 30
)

end
EOT



# -------------------------
# 分流页面
# -------------------------

cat > files/usr/lib/lua/luci/view/doornet2_shunt/main.htm <<'EOT'
<%+header%>

<h2>DoorNet2 分流总节点</h2>

<table class="table">

<tr>
<td>国内流量</td>
<td>
IPv4 直连<br>
IPv6 直连
</td>
</tr>


<tr>
<td>国外流量</td>
<td>
IPv4 代理
</td>
</tr>


<tr>
<td>国外IPv6</td>
<td>
禁止
</td>
</tr>


<tr>
<td>PassWall</td>
<td>
<%=luci.sys.exec("uci get passwall.@global[0].enabled 2>/dev/null")%>
</td>
</tr>

</table>


<%+footer%>
EOT



# -------------------------
# 菜单
# -------------------------

mkdir -p files/usr/share/luci/menu.d


cat > files/usr/share/luci/menu.d/doornet2.json <<'EOT'
{
"admin/status/doornet2":
{
"title":"DoorNet2状态",
"order":20,
"action":
{
"type":"template",
"path":"doornet2_status/main"
}
},

"admin/services/doornet2_shunt":
{
"title":"分流总节点",
"order":30,
"action":
{
"type":"template",
"path":"doornet2_shunt/main"
}
}
}
EOT



echo "===== 完成 ====="

find files/usr/lib/lua/luci -name "*doornet2*"

