# DoorNet2 OpenWrt / iStore Firmware

专为 **DoorNet2 / Rockchip RK3399** 定制的 OpenWrt 固件项目。

本项目基于 OpenWrt / LEDE Rockchip 进行定制，重点实现：

- TF 卡优先启动
- eMMC 自动回退
- TF / eMMC 双独立系统
- 安全在线升级
- 在线升级防误刷
- TF 整卡容量支持
- 在线升级后保持 TF 整卡容量
- iStore / OPKG 在线软件安装
- QuickStart 首页
- Argon Web UI
- DoorNet2 专用在线升级系统

---

# 当前稳定状态

## TF 主系统

```text
DoorNet2 OpenWrt R23
QuickStart + Argon
RootFS ≈ 29.2 GB
TF Partition ≈ 29.7 GB
