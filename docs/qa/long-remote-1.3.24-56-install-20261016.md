# 远程长截图提示修正试用版 1.3.24 build 56

2026-10-16。固定源码 `8832a4f`，只调整长截图辅助窗口共享策略，并确保采集流缺少自身排除时停止启动。原包 build 55 的 9 个辅助窗口共享状态均为 0；维护者确认通过远程桌面操作。新包逐项验收依照[安装规范](../operations/install-and-permissions.md)，旧包结果不代替本包。

| 检查项 | 结果 | 证据或待办 |
| --- | --- | --- |
| 固定包、版本/build、源码、SHA-256 | 通过 | dist/LibreShot-1.3.24-56-trial/LibreShot-1.3.24-56.dmg；1.3.24 build 56；源码 8832a4f；SHA-256 393cb19f2e5155a247a2374dd74830f398ce320ad12341947fffd767ddf26777 |
| DMG、主应用/helper 签名、安装一致性 | 通过 | package/install --plan/install 均退出 0；ad-hoc、universal；安装与候选主程序 SHA-256 均为 9504be2f4675c9883145e660cd5d4fff73c9f3a17500bf457d28965a8193eb03 |
| 正常退出、清理与安装路径 | 通过 | 正常菜单退出后 status 无主进程；固定 /Applications/LibreShot.app，旧安装、候选和 archive 入废纸篓；retired-apps.json；Finder 精确路径启动 |
| 屏幕录制授权 | 通过 | 新版实际报缺失；退出后移除旧条目，用户完成系统身份验证；确认旧项消失，+ 精确添加 file:///Applications/LibreShot.app/，预览 1.3.24，新条目 on；同包重启前后截图均成功 |
| 输入监控及 Option | 通过 | 新包提示失效；退出时移除旧项，确认无项目，再添加当前完整路径，条目 on；重开后缺失提示消失，原 Option 开关仍 1；维护者通过远程桌面联合验收，确认“Option 正常，边框和提示都能看到” |
| 重启前区域截图、标注、保存、剪贴板 | 通过 | 菜单区域截图，公开文字和红色矩形；/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-16 14.57.30.png，990×460；before-restart.png 可解码、内容正确；剪贴板像素一致 |
| 同包重启后区域截图、标注、保存 | 通过 | 正常菜单退出，status none，Finder 同路径重开；公开文字及画笔 Screenshot 2026-10-16 14.58.05.png，990×460；after-restart.png 内容正确、剪贴板像素一致，无再次授权 |
| OCR helper 实际调用 | 通过 | 最终安装包实际 OCR 识别公开 ROW000–005；ocr-result.txt，末行 sample 被识别为 samole，非准确率专项 |
| 原设置保留 | 通过 | 备份与当前 17 项语义比较全一致，包含书签、自动保存、Option、登录、工具、快捷键和辅助线；settings-preservation.json |
| 共享策略集成检查 | 通过 | 实际安装副本 9 个窗口全为 sharing=1，allWindowSharingReadOnly=true，检查退出 0；window-visibility.json；对照 build55 全 0、退出 1；策略不替代 UU 实际画面 |
| 长截图自身过滤及输出 | 通过 | 最终安装副本诊断进程 10225；excludedCount=1；8 帧、990×5620（逻辑 495×2810）成功导出，编号 000–069 各一次；图片中未见提示或边框；详情见下方 |
| UU 远程实际可见性 | 通过 | 维护者在远程客户端确认“Option 正常，边框和提示都能看到”；本次“点长截图后选区和提示消失”问题完成用户确认 |
| 交付、发布与回退 | 安装与本次修正验收通过 | 已恢复 Finder 正常启动；同包截图保存、公开长图、实体 Option 和远程边框/提示可见性均通过；未发布/推送/回复 Issue |


## 同包专项与验收边界

长截图从本包正常 UI 的区域截图工具栏启动，公开主屏选区为逻辑 495×650、Retina 2×，没有借用旧包或 Preview。使用完整路径 `open --env LIBRESHOT_LONG_CAPTURE_TRACE=1 /Applications/LibreShot.app` 启动仅数字诊断，不重签名、不改变系统全局环境。自身应用过滤数量 1；9 个辅助窗口都共享为 readOnly；回放 0→122→360→720→1080→1440→1320→1800→2160 逻辑像素，最终实际位置与设定一致，接受 8 帧，输出 990×5620 像素。最终 3 个观察帧稳定，render-validation 和 finish 均 success。保存 `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-16 15.00.33.png`，公开 PNG 为 installation-qa/public-long-5620.png，剪贴板解码像素一致；Vision 编号 000–069 连续各一次，人工查看无可见重复、缺行或辅助 UI。数值日志 long-capture-trace.log、识别结果 public-long-ocr.txt 与 public-long-rows.json。

测试后正常菜单退出诊断进程，status 确认无主进程，由 Finder 同路径正常重开；最终设置仍保留 Option=1、无输入监控缺失提示。公开窗口复位，供维护者通过远程桌面执行“实体双击 Option→公开区域框选→工具栏长截图→查看边框/采集提示→Esc 取消”联合验收。维护者对该联合验收明确回复“Option 正常，边框和提示都能看到”，客户端画面及实体触发通过；此确认来自维护者实际远程操作，不以 WindowServer 元数据或代理截图代替。没有访问或保存原 Codex 私人聊天帧，也不宣称所有原场景“未接上”问题已消除。
