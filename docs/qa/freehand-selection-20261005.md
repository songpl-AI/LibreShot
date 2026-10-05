# 画笔选框与手势容差修复

2026-10-05，基于 1.3.3 之后的 `bbae32c`，工作分支 `codex/pen-selection-gestures`。本次为工作区修复，未替换已安装 1.3.3 或发布新版本。

## 复现

先添加闭合笔迹（起终点相邻、中间点跨越较大区域）与轻微抖动检查，再运行 `bash tests/run-issue9-checks.sh`。修改前退出 1，四项失败：完整笔迹选框、从选框内部移动、选中笔迹轻点不移动、空白轻点不新增笔迹。日志 `/tmp/libreshot-pen-before.log`。

## 原因与修复

- 原先画笔选中框只使用起点和终点，闭合或曲折路径的中间点被遗漏。新增 `Annotation.selectionBounds`，画笔与模糊按所有采样点和线宽计算，选框绘制和移动命中共用它。
- 原先画笔仅在笔迹上可拖动，选框内部没有对应命中。选中笔迹的框内部现在可移动，但其他标注的可见内容仍优先；画笔不新增缩放控制点。
- 标注移动原先从零距离事件就改变坐标，画笔/模糊也会提交点击小点。加入 5 点拖动门槛，整次拖动跨过门槛后保持拖动判定；真实绘制按路径曾达到的距离判断，不能只按终点距离，否则会丢失闭合笔迹。

## 验证与边界

- 最终 `LIBRESHOT_ISSUE9_QA=/tmp/libreshot-pen-selection-qa bash tests/run-issue9-checks.sh` 退出 0，92 项 PASS；新增检查还覆盖闭合笔迹完整性、抖动不插入撤销步骤、移动回原位、框内部移动光标。
- `bash tests/run-toolbar-checks.sh` 退出 0，既有选择、绘制、重叠命中、图形缩放、选区优先级、快捷键、保存等回归通过。日志 `/tmp/libreshot-pen-toolbar.log`。
- 原生 SwiftUI 渲染检查确认浅蓝选框包含整条笔迹，图片 `/tmp/libreshot-pen-selection-qa/freehand-selection.png`；临时日志与图片可能被系统清理。
- `git diff --check` 通过。没有新增后台监听、修改权限或改变图片导出实现。
- 尚未进行完整新包的实体鼠标验收；本次验证不能写成已安装版本已经修复。轻点画笔/模糊不再生成点状标注，是减少误触的明确行为变化。

## 本机试用安装

用户随后要求本机安装以便试用。已构建 ad-hoc Release 1.3.4 build 22，输出 `dist/LibreShot-1.3.4-22-local-freehand`；归档、DMG 校验及嵌套签名检查通过。正常退出 1.3.3 后替换 `/Applications/LibreShot.app`，旧应用保存在 `dist/install-backup-20261005-before-1.3.4-22/LibreShot.app`。版本、构建号与新包一致，应用已成功启动；尚未上传 GitHub。

新启动出现输入监控缺失提示，开始在系统设置更新 LibreShot 对应旧记录。用户已完成系统 Touch ID/密码验证；通过完整路径重新添加 `/Applications/LibreShot.app` 并启动新版后，快捷键设置保留“双击 Option 启动区域截图”，输入监控缺失提示已消失。未完成实体鼠标截图验收，接下来由用户测试实际绘制与拖动手感。源码差异与基线记录在包目录 `SOURCE-CHANGES.patch` / `BUILD-INFO.json`。

## 用户反馈与验收纠正

用户随后实际截图提示“尚未获得屏幕录制权限”。此前仅输入监控缺失提示消失的检查通过；屏幕录制未通过，不能将启动成功写成可以正常截图。当前状态：1.3.4 build 22 已安装，录屏恢复及同包重启前后截图保存待完成。今后每次新包执行 [安装与授权验收规范](../operations/install-and-permissions.md)，用每包独立清单记录结果。

## 重新安装与基础验收通过（2026-10-05 15:44）

用户明确要求每次新包移除旧应用副本。确认原 PID 49018 的执行路径和 Info.plist：原来报错的也是 `/Applications/LibreShot.app` 1.3.4 build 22，并非旧版。正常退出后，将 65 个正式/旧 Preview 同名应用副本（包括已安装副本及旧归档内副本）移入可恢复废纸篓；清单为包目录 `retired-apps.json`。保留最新候选、DMG、源码、测试 fixture 和历史记录。旧归档中的应用已移走，不能再将其视为完整可用归档。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 候选包、版本/build、源码、SHA-256 | 通过 | 1.3.4/22；源码基线与差异见 BUILD-INFO.json / SOURCE-CHANGES.patch；DMG SHA-256 55cbef02542d3e48e8a0dcedc4b13d0a781a69e319e707ffcb7ea5e1955c86cc；SHA256SUMS OK |
| 签名和安装内容 | 通过 | 候选及安装副本严格签名检查通过；重启后逐文件内容与候选一致；本轮复用已核验产物，未重编译或重签名 |
| 旧实例退出及新进程 | 通过 | 菜单正常退出并确认无进程；最终 PID 66310 为 /Applications/LibreShot.app/Contents/MacOS/LibreShot |
| 屏幕录制恢复 | 通过 | 旧记录 on 但实际失败；退出后移除录屏旧项，用完整路径重新添加并重开；未使用 tccutil，未更改其他应用权限 |
| 输入监控 | 状态通过、实体触发待验 | 重启前后双击 Option 开关保留为开启，无输入监控缺失提示；工具不支持纯修饰键，本轮未实测实体按键 |
| 重启前截图/保存 | 通过 | 应用菜单区域截图，公开 fixture 框选并画笔标注；Screenshot 2026-10-05 15.42.33.png，1010×1250；证据 installation-qa/before-restart.png |
| 同包重启后截图/保存 | 通过 | 菜单退出、目标路径重启，无再次授权；Screenshot 2026-10-05 15.44.31.png，1010×1250；证据 installation-qa/after-restart.png |
| 文件内容及保存目录 | 通过 | 两张 PNG 均可解码，公开文字完整、透明圆角保留；原保存目录不变，第二张直接保存 |
| 剪贴板像素核对 | 待验 | 完成动作调用复制与自动保存；本轮没有独立读取并比对剪贴板数据 |
| 新功能/其他环境 | 部分通过 | 实体画笔绘制、导出通过；不规则闭合笔迹与拖动手感由用户继续试用；Intel/旧系统/多屏未测 |
| 最终状态 | 基础安装验收通过 | 可以测试新功能；尚未上传 GitHub |

本轮桌面工具仍有菜单栏应用首次绑定超时、窗口 reopen 行为；重新读取状态并使用应用菜单完成真实流程。屏幕上有其他应用的授权弹窗，本轮未操作该无关权限，仅裁剪公开 fixture 内容。

## 默认工具调整（同日，源码验证）

按用户要求，普通截图框选完成及长截图/图片编辑入口统一将 selectedTool 设置为 nil，即工具栏“选择/移动”。不再自动选择矩形；用户主动点击工具或使用工具快捷键后才进入对应绘制模式。已有工具栏快照回归断言随行为更新。

- tests/run-toolbar-checks.sh 退出 0，日志 /tmp/libreshot-default-select-toolbar.log。
- tests/run-issue4-checks.sh 退出 0，图片编辑、长图坐标与导出回归通过；日志 /tmp/libreshot-default-select-editor.log。
- git diff --check 通过；生产源码中已无 selectedTool = .rectangle 的默认赋值。
- 此修改尚未重新打包安装，当前已安装的 1.3.4 build 22 仍为修改前包。下次换包须执行安装与授权规范，不能把源码测试通过写成安装副本已更新。
