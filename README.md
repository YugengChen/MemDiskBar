# MemDiskBar

一个极简的 macOS 菜单栏小工具，实时显示内存、储存占用和主机功耗。

```
[内存图标] ▮ 6.2/8GB    [硬盘图标] ▮ 163/245GB    ⚡ 3.8W
```

## 功能

- 显示 已用/总量，可在菜单中切换为百分比
- 竖向小进度条 + 颜色提示：≥75% 橙色，≥90% 红色
- 内存算法与「活动监视器」一致：App 内存 + 联动内存 + 被压缩内存
- 储存可用空间与「系统设置 → 储存空间」一致（包含可清除空间）
- 主机功耗读取 SMC 传感器 `PSTR`（整机总功耗），无需管理员权限；不含外接显示器，可在菜单中关闭
- 每 3 秒刷新，几乎不占资源
- 菜单内可一键开启开机自动启动

## 安装

需要 Xcode 命令行工具（`xcode-select --install`），macOS 13 及以上，Apple Silicon。

```bash
git clone https://github.com/YugengChen/MemDiskBar.git
cd MemDiskBar
./build.sh
```

脚本会编译并安装到 `~/Applications/MemDiskBar.app`，然后自动启动。

## 开机启动

点击菜单栏中的 MemDiskBar → 勾选「开机自动启动」，或在终端执行：

```bash
~/Applications/MemDiskBar.app/Contents/MacOS/MemDiskBar --login on
```

关闭用 `--login off`。

## 卸载

```bash
~/Applications/MemDiskBar.app/Contents/MacOS/MemDiskBar --login off
pkill -x MemDiskBar
rm -rf ~/Applications/MemDiskBar.app
```
