# 自身应用过滤试用版 1.3.24 build 55

2026-10-14。源码 `8219a56457cbcb0dc3a42b876cee515ed7792cee`，只修正长截图启动时自身应用元数据查找；保留 build 54 的局部重绘修正。依据[新包安装与授权验收规范](../operations/install-and-permissions.md)执行，公开实验与修复边界见[控制输入复查](long-capture-controlled-repro-20261014.md)。此记录随实际证据更新，不用旧包结果替代新包验收。

| 检查项 | 结果 | 证据或待办 |
| --- | --- | --- |
| 固定包、源码、版本/build、SHA-256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.24-55-trial/LibreShot-1.3.24-55.dmg`；1.3.24 build 55；DMG SHA-256 `267fefa6fb4c1677f98410162ce2fa7a817e1fff4fd32d52788978c48b34bb8a`；SOURCE.json |
| DMG、主应用/helper 签名与安装内容 | 通过 | 固定脚本 package/install 退出 0；universal、ad-hoc；安装与候选主程序 SHA-256 同为 `76df789827dcf630bdcb9ce95adba7e508bd41db7bccb05405376c65fb5278a3`；build.log、INSTALL.json |
| 旧实例退出、清理、安装路径 | 通过 | 正常退出后替换至 `/Applications/LibreShot.app`；旧安装、候选、archive 移入废纸篓，见 retired-apps.json；偏好备份 pre-upgrade-preferences.plist；新进程 86051 路径经 status 确认 |
| 屏幕录制记录恢复 | 通过 | 新版实际报缺失；正常退出，移除旧项并确认消失；重新添加当前完整路径，系统列表 `LibreShot.app` 开关 1。最终安装副本重启前后实际截图均成功 |
| 输入监控记录及 Option 开关 | 监听提示通过／实体触发待验 | 应用退出时移除旧项，CUA 确认“无项目”；重新选择 `file:///Applications/LibreShot.app/`，预览版本 1.3.24，添加后列表 on；Finder 重开后设置缺失提示消失，双击 Option 开关仍为 1。本包实体触发仍须单独记录 |
| 重启前区域截图、标注、保存、剪贴板 | 通过 | 菜单区域截图，CGEvent 框选公开文字、红色矩形标注，完成后保存 `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 19.01.59.png`；470×220，before-restart.png，人工查看内容正确；剪贴板解码像素与保存 PNG 一致 |
| 同包重启后区域截图、保存 | 通过 | 正常菜单退出，status 无进程，Finder 同路径重开进程 1134；区域截图加画笔保存 `Screenshot 2026-10-14 19.03.23.png`，470×220，after-restart.png；剪贴板像素一致，无再次授权提示 |
| OCR helper | 通过 | 最终副本真实公开选区识别五行中英文字，OCR 结果窗口 140 字符；installation-qa/ocr-result.txt；首行 0 被识别为 O，非准确率专项 |
| 原设置保留 | 通过 | 备份与当前容器偏好 17 项语义比较全部一致，包含保存书签、自动保存、Option、登录启动、工具设置/样式、快捷键、左键动作及辅助线；installation-qa/settings-preservation.json |
| 本包长截图专项 | 公开场景通过／原 Codex 场景待验 | 本包诊断进程 2355 确认 excludedCount=1；控制序列导出 495×2810、8 帧，真实滚轮导出 495×1730、6 帧，两轮成功收尾；下方详记 |
| 最终交付状态、发布/回退 | 基础截图与长截图公开验收通过／Option 实体待验 | 已恢复 Finder 正常启动，无诊断环境，可以试用本次修正；Option 单列待验，原 Codex 页面及全部间歇报错不宣称已解决；未推送、发布、回复 Issue。回退包仍需独立复验 |

桌面工具无法连接主应用时使用用户此前明确授权的 AppleScript/System Events。它能读取权限和设置，但画布拖拽未取得成功证据；维护者明确回复“允许，继续自动验收”后，才使用 CGEvent 在公开测试窗口框选和标注。用户确认曾手动滚动上一轮自动窗口，受叠加输入影响的轮次不列为产品通过或失败。


## 本包公开长截图与剩余边界

维护者明确允许 CGEvent 模拟公开窗口鼠标输入后完成基础验收。诊断仅以 `open --env LIBRESHOT_LONG_CAPTURE_TRACE=1 /Applications/LibreShot.app` 打开同一已验收安装副本，没有重编译、重签名或改变系统全局环境。安装副本本体始终 build 55。数值日志只保存本进程的长截图原因、尺寸和位移，不保存用户聊天帧。

初次滚动测试受到旧 OCR 公开 fixture 置顶遮挡：源滚动位置改变，但采集的画面保持旧 OCR 窗口，全部去重、保持 1 帧；取消此轮，不记作长截图成功或产品匹配失败。关闭遮挡窗口后复位并重新建基线。测试 fixture 最终使用正常窗口层级；早期浮动窗口选区自动化未进入编辑，亦不记作生产缺陷。

- 控制序列：公开 120 行编号，选区 495×650，位置 0→122→360→720→1080→1440→1320→1800→2160，2 秒开始、每 4 秒一段。最终实际滚动位置 2160，接受 8 帧、高度 2810。自身排除 1；3 个收尾帧稳定，render-validation 与 finish 均 success。保存 `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 19.14.51.png`；controlled-long-2810.png，剪贴板像素一致；Vision 编号 000–069 按序各一次，人工查看无可见断行或重复。controlled-long-trace.log、controlled-long-ocr.txt、controlled-long-rows.json。
- 鼠标滚轮：CGEvent 像素滚动，实际位置 0→120→360→600→480→840→1080；采样间隔至少 1.2 秒。回滚 120 时接受数保持 4、高度保持 1250，回到后续位置时仅追加新内容；最终 6 帧、1730。finish 与 render-validation 均 success，自身排除 1。保存 `Screenshot 2026-10-14 19.17.45.png`；wheel-long-1730.png，剪贴板像素一致；编号 000–042 按序各一次，人工查看无可见断行/重复。wheel-status.json、wheel-long-trace.log、wheel-long-ocr.txt、wheel-long-rows.json。

上述是公开简单页面、分段滚动和短回访验收；不证明原 Codex 聊天中的所有间歇“未接上”已消除，也未覆盖快速连续触控板惯性滚动、复杂动态网页或所有局部重绘。没有为通过测试放宽原像素接缝或失败收尾要求。公开帧污染回放测试通过，保留正确拒绝、同位置恢复、成功导出行为。

测试后正常菜单退出诊断进程，status 确认无主进程，关闭本轮测试窗口，由 Finder `/Applications/LibreShot.app` 正常重开；未留下诊断环境。维护者收到本包双击 Option 加 Esc 的实体验收请求，回答另记。
