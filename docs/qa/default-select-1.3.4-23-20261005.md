# 1.3.4 build 23 默认选择/移动 · 本机安装验收

日期：2026-10-05。本地试用，尚未公开发布。执行 [安装与授权规范](../operations/install-and-permissions.md)。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包、源码和校验值 | 通过 | dist/LibreShot-1.3.4-23-local-default-select；SHA-256 8de9978b6e312eecc887a1b3eef407bbc1930cb11a64e3fed8b58abb74878098；BUILD-INFO.json 与 SOURCE-CHANGES.patch 保存本地源码基线/差异 |
| 签名、DMG、安装内容 | 通过 | 构建脚本退出 0；主应用/helper 校验；只读挂载签名和内容比对；安装副本逐文件内容一致 |
| 旧实例与冗余副本 | 通过 | 正常退出 build 22，三份旧应用移入废纸篓；retired-apps.json 为清单；保留设置和旧 DMG |
| 录屏与输入监控 | 通过状态检查 | 应用退出后分别移除旧记录，用 /Applications/LibreShot.app 重新添加；新版重启前后输入监控提示消失，Option 设置仍开启；无需 tccutil |
| 重启前截图、标注、保存 | 通过 | /Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-05 15.59.39.png；公开 fixture；用户式点击画笔并绘制；installation-qa/before-restart.png |
| 同包重启后截图、保存 | 通过 | /Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-05 16.00.58.png；installation-qa/after-restart.png；无需再次授权或选择保存目录 |
| 默认工具 | 通过实测 | 重启前后框选后 AX 为“选择/移动，已选中”，矩形未选中；主动点击画笔后才绘制 |
| 长截图图片编辑默认工具 | 源码回归通过 | 图片编辑入口设置为 nil；tests/run-issue4-checks.sh 已通过；本包未重新执行完整滚动长截图 |
| 实体双击 Option、剪贴板像素比对 | 待验 | 工具不支持纯修饰键；完成按钮调用复制但未单独读取剪贴板核验 |
| 最终状态 | 基础安装验收通过 | 可以交给用户测试默认工具；无 GitHub 发布；Intel/旧系统/多屏未验 |

源码变更的工具栏及图片编辑回归日志：/tmp/libreshot-default-select-toolbar.log、/tmp/libreshot-default-select-editor.log；构建日志 /tmp/libreshot-1.3.4-23-build.log。此包包含此前画笔选框修复，不重复与本次修改无关的 OCR 长循环。桌面工具首次启动菜单栏应用绑定超时，第二次读取设置成功；验收使用原生菜单与真实拖动。

## 用户验收与发布批准

用户试用反馈“现在看着好像没有什么问题了”，随后明确批准上传源码、更新文档并发布 build 23。实体 Option 完整边界仍不据此标记通过。发布使用同一已验收 DMG，不重新构建或重签名；发布结果见后续记录。
