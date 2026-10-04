#!/bin/bash

set -e

echo "===== DoorNet2 Upgrade Feed Fix ====="

cd ~/DoorNet2-iStoreOS


echo "[1/7] 清理旧错误 feed..."

sed -i '/src-link custom/d' feeds.conf.default


echo "[2/7] 检查插件目录..."

if [ ! -d "feeds/custom/luci-app-doornet2-upgrade" ]; then
    echo "错误：找不到 feeds/custom/luci-app-doornet2-upgrade"
    exit 1
fi


echo "[3/7] 添加正确 feed..."

echo "src-link custom $(pwd)/feeds/custom" >> feeds.conf.default


echo "[4/7] 更新 custom feed..."

./scripts/feeds update custom


echo "[5/7] 安装升级插件..."

./scripts/feeds install -p custom luci-app-doornet2-upgrade


echo "[6/7] 重新生成配置..."

make defconfig


echo "[7/7] 检查结果..."

echo
grep doornet2 .config || true

echo
echo "===== 完成 ====="

