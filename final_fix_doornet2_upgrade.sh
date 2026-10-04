#!/bin/bash

set -e

cd ~/DoorNet2-iStoreOS

echo "===== DoorNet2 Upgrade Final Fix ====="


echo "[1] 清理错误feed缓存"

rm -rf feeds/custom
rm -f feeds/custom.index


echo "[2] 删除错误注册"

sed -i '/luci-app-doornet2-upgrade/d' package/Makefile


echo "[3] 创建标准package目录"

mkdir -p package/custom/luci-app-doornet2-upgrade


echo "[4] 如果插件还在备份目录，恢复"

if [ -d package/luci-app-doornet2-upgrade ]; then
    cp -a package/luci-app-doornet2-upgrade/* \
    package/custom/luci-app-doornet2-upgrade/
fi


echo "[5] 创建custom入口"

cat > package/custom/Makefile <<'MAKE'
include $(TOPDIR)/rules.mk

SUBDIRS:=luci-app-doornet2-upgrade
MAKE


echo "[6] 注册custom package"

grep -q "custom" package/Makefile || \
echo '$(eval $(call PackageDir,custom,custom))' >> package/Makefile


echo "[7] 删除旧配置缓存"

rm -rf tmp/.config-package.in*
rm -rf tmp/info


echo "[8] 重新扫描package"

make package/symlinks


echo "[9] 生成配置"

make defconfig


echo
echo "===== RESULT ====="

grep doornet2 .config || true

echo
echo "完成"

