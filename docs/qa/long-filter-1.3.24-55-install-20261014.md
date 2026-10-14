# 自身应用过滤试用版 1.3.24 build 55

2026-10-14。源码 `8219a56457cbcb0dc3a42b876cee515ed7792cee`，只修正长截图启动时自身应用元数据查找；保留 build 54 的局部重绘修正。依据[新包安装与授权验收规范](../operations/install-and-permissions.md)执行，公开实验与修复边界见[控制输入复查](long-capture-controlled-repro-20261014.md)。此记录随实际证据更新，不用旧包结果替代新包验收。

| 检查项 | 结果 | 证据或待办 |
| --- | --- | --- |
| 固定包、源码、版本/build、SHA-256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.24-55-trial/LibreShot-1.3.24-55.dmg`；1.3.24 build 55；DMG SHA-256 `267fefa6fb4c1677f98410162ce2fa7a817e1fff4fd32d52788978c48b34bb8a`；SOURCE.json |
| DMG、主应用/helper 签名与安装内容 | 通过 | 固定脚本 package/install 退出 0；universal、ad-hoc；安装与候选主程序 SHA-256 同为 `76df789827dcf630bdcb9ce95adba7e508bd41db7bccb05405376c65fb5278a3`；build.log、INSTALL.json |
| 旧实例退出、清理、安装路径 | 通过 | 正常退出后替换至 `/Applications/LibreShot.app`；旧安装、候选、archive 移入废纸篓，见 retired-apps.json；偏好备份 pre-upgrade-preferences.plist；新进程 86051 路径经 status 确认 |
| 屏幕录制记录恢复 | 系统记录通过／实际截图待验 | 新版实际报缺失；正常退出，移除旧项并确认消失；重新添加当前完整路径，系统列表 `LibreShot.app` 开关 1。未把列表开启当作真实截图通过 |
| 输入监控记录及 Option 开关 | 监听提示通过／实体触发待验 | 应用退出时移除旧项，CUA 确认“无项目”；重新选择 `file:///Applications/LibreShot.app/`，预览版本 1.3.24，添加后列表 on；Finder 重开后设置缺失提示消失，双击 Option 开关仍为 1。本包实体触发仍须单独记录 |
| 重启前区域截图、标注、保存、剪贴板 | 待验 | CUA 连接 LibreShot 反复 native pipe closed；公开 OCR fixture 可连接。AppleScript 已打开区域截图遮罩，但工具拖拽没有确认进入编辑状态，无成功 PNG 证据 |
| 同包重启后区域截图、保存 | 待验 | 必须先完成首次真实保存，再正常退出、Finder 同路径重开复验 |
| OCR helper | 待验 | 签名已核验，实际调用另记 |
| 原设置保留 | 通过 | 备份与当前容器偏好 17 项语义比较全部一致，包含保存书签、自动保存、Option、登录启动、工具设置/样式、快捷键、左键动作及辅助线；installation-qa/settings-preservation.json |
| 本包长截图专项 | 待验 | 需 live trace 确认自身排除数量，控制滚动及成功收尾导出；build 54 的 2810px 公开长图不替代此项 |
| 最终交付状态、发布/回退 | 已安装，验收未完成 | 尚不能宣称安装验收通过或交付新功能测试；未推送、发布、回复 Issue。回退包仍需独立复验 |

桌面工具无法连接主应用时使用用户此前明确授权的 AppleScript/System Events。它能读取权限和设置，但画布拖拽未取得成功证据；已请求仅在公开窗口使用 CGEvent 模拟输入的明确授权，未收到授权前不执行该输入方式。用户确认曾手动滚动上一轮自动窗口，受叠加输入影响的轮次不列为产品通过或失败。
