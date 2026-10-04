#!/bin/bash

set -e

cd ~/DoorNet2-iStoreOS


echo "===== DoorNet2 Upgrade Files Install ====="


echo "[1] 创建 files 目录"


mkdir -p files/usr/lib/lua/luci/controller
mkdir -p files/usr/lib/lua/luci/view/doornet2_upgrade
mkdir -p files/usr/bin
mkdir -p files/etc/doornet2


echo "[2] 复制升级程序"


cp package/custom/luci-app-doornet2-upgrade/root/usr/bin/* \
files/usr/bin/


echo "[3] 复制 LuCI 控制器"


cp package/custom/luci-app-doornet2-upgrade/root/usr/lib/lua/luci/controller/* \
files/usr/lib/lua/luci/controller/


echo "[4] 复制 LuCI 页面"


cp package/custom/luci-app-doornet2-upgrade/root/usr/lib/lua/luci/view/doornet2_upgrade/* \
files/usr/lib/lua/luci/view/doornet2_upgrade/


echo "[5] 复制版本信息"


cp -a files/etc/doornet2/version.json \
files/etc/doornet2/version.json 2>/dev/null || true


echo "[6] 设置权限"


chmod +x files/usr/bin/doornet2-*


echo "[7] 检查"


find files/usr/bin -name "doornet2*" -ls

echo

find files/usr/lib/lua/luci/controller -name "*doornet2*" -ls


echo "===== DONE ====="

