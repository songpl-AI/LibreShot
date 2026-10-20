# Dock 图标开关 Preview 自测（2026-10-20）

源码 `8c96dd6`。按 [Preview 试用说明](preview-trial.md) 构建独立的 `LibreShot Preview.app`，未替换 `/Applications/LibreShot.app`，未做安装授权验收。本记录只覆盖“设置里显示/隐藏程序坞图标”的功能自测。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码 | 通过 | `dist/LibreShot-Preview-1.3.28-dock-icon/LibreShot Preview.app`；1.3.28 / 82；源码 `8c96dd6` |
| 签名、架构 | 通过 | ad-hoc；`arm64 x86_64`；`verify_release_signing.sh --allow-ad-hoc` |
| 单元检查 | 通过 | `bash tests/run-activation-policy-checks.sh`：Dock 开/关映射 `.regular`/`.accessory`，面板只从 `.accessory` 借用 `.regular` |
| 启动默认状态 | 通过 | 新装预览启动后 `ApplicationType = UIElement`，程序坞列表无 LibreShot |
| 打开开关 | 通过 | 勾选“在程序坞中显示图标”后，`ApplicationType = Foreground`，Dock 进程的 `list 1` 出现 `LibreShot Preview`；`showInDock = 1` |
| 关闭开关 | 通过 | 取消勾选后立即回到 `UIElement`，Dock 列表中的 `LibreShot Preview` 消失；`showInDock = 0` |
| 重启保持 | 通过 | 开启后终止进程并重新启动，仍为 `Foreground`，Dock 图标仍在；设置为 `0` 时重启为 `UIElement` |
| 设置窗口 | 通过 | 关闭开关时“偏好设置”窗口保持打开，可继续操作 |
| 用户实际试用 | 通过 | 2026-10-20 用户确认“看着没问题”；范围为显示/隐藏与重启保持 |
| 保存/另存为面板的临时切换 | 待验 | 代码改为按用户偏好恢复（[AppActivationPolicy.swift](../../LibreShot/LibreShot/Core/AppActivationPolicy.swift)、[CaptureService.swift](../../LibreShot/LibreShot/CaptureService.swift)）；需实际触发保存面板才能取证 |
| 实际截图与保存 | 未执行 | 本记录不是安装验收；Preview 未授权屏幕录制，未触发截图 |
| 屏幕录制/输入监控 | 不适用 | 未替换安装副本，未改动系统授权 |

## 自测命令与证据

```sh
# 进程类型：UIElement = 仅菜单栏；Foreground = 有 Dock 图标
lsappinfo info -only ApplicationType "$(lsappinfo find bundleid=com.allensong.LibreShot.Preview)"

# Dock 实际图标（不截图，读 Dock 的辅助功能列表）
osascript -e 'tell application "System Events" to tell process "Dock" to get name of every UI element of list 1'

# 持久化值
defaults read com.allensong.LibreShot.Preview showInDock
```

测试完成后已退出预览、删除测试写入的 `showInDock`，并把开关恢复为关闭。

## 未覆盖

- 未在正式安装副本 `/Applications/LibreShot.app` 上验证；正式替换、授权与同包重启前后实际截图保存仍需按 [安装与授权验收规范](../operations/install-and-permissions.md) 执行。
- 未验证保存面板前后的 Dock 图标闪现行为，未验证 `⌘Q`、Dock 右键菜单、登录时启动的表现。
- 未在 Intel、多显示器、macOS 13–15 上复测。

## 结论

功能自测通过，Preview 可直接试用：从 `dist/LibreShot-Preview-1.3.28-dock-icon/LibreShot Preview.app` 启动，打开设置 > 基本设置 > 程序坞。正式交付前仍需换包并补安装验收。

## 用户确认（2026-10-20）

用户在实际桌面试用 Preview 后确认“看着没问题”。确认范围仅限 Dock 图标的显示/隐藏及重启保持；实际截图保存、安装副本授权仍未验收。正式交付前按 [安装与授权验收规范](../operations/install-and-permissions.md) 换包并补重启前后截图保存。
