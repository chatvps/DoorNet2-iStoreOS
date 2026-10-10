# DoorNet2-V1.1.1 本地构建脚本（初版/待验证）

**来源：** 用户提供的 DoorNet2-V1.7 GitHub Actions YAML，SHA256
`a9b27a43327cf24be991eddf289103ce1c2f57d2d1fec69e83a2c29c208837cf`。

迁移方式：保留 V1.7 的 3-48、56 步原始脚本逻辑（拆分成可本地运行的脚本），不迁移
1（云端 Ubuntu 初始化）、2（checkout）、49-53（Actions artifacts）、54-55（自动发布）。
将 `DoorNet2-V1.7` 修改为 `DoorNet2-V1.1.1`，编译步骤由 `make -j$(nproc)` 改成
`make -j${DOORNET2_JOBS:-2}`，失败仍回退 `make -j1 V=s`。

使用：

```bash
cd ~/Projects/DoorNet2-iStoreOS
bash scripts/local-build/v1.1.1/run.sh check
```

静态检查后，需要审阅并提交 V1.1.1 到 GitHub，检查仓库干净，再运行：

```bash
bash scripts/local-build/v1.1.1/run.sh build
```

Docker 运行环境：先前在本机成功构建的 `doornet2-build:ubuntu22.04`，
UID/GID 1000 普通用户 `builder`。单次容器贯穿全部步骤，构建中持久保留
源码、下载缓存、构建输出；日志写入 `~/Projects/DoorNet2-build-logs`。

**签名：** V1.7 原本支持持久和临时密钥。若本地有 OpenWrt usign 私钥，可通过
`DOORNET2_SIGNING_KEY_FILE=/secure/path/to/key` 环境变量传入（Docker read-only
mount）。严禁把私钥上传 GitHub。未指定时使用临时 key，**不可假定 OTA 跨版本信任连续**。

**安全限制：** 本脚本不会 git push、不会上传 OPKG、不会创建 GitHub Release。
完整编译成功不代表实机可启动。先看全部审计日志和固件元数据，先在 TF 测试，
确认后才考虑 eMMC。GitHub 发布脚本需要后续单独设计和测试。

**注意：** 当前只完成脚本静态校验，尚未在用户的 GitHub 仓库实际运行完整编译。

## 将编译环境托管在 GitHub

仓库还应保存本目录内的 `Dockerfile` 和 `apt-packages.txt`。
另一台 Linux 电脑可在仓库根目录运行：

```bash
sudo docker build --build-arg BUILD_UID="$(id -u)" \
  --build-arg BUILD_GID="$(id -g)" \
  -t doornet2-build:ubuntu22.04 scripts/local-build/v1.1.1
```

首轮仅运行 `bash scripts/local-build/v1.1.1/run.sh check`。
