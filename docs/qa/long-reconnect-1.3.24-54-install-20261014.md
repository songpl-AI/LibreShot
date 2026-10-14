# 局部重绘修复试用版 1.3.24 build 54

2026-10-14。固定源码e7779fc，包含局部重绘唯一零位移证明；之后只补QA文档，不改应用签名。源码复现与220项优化回归见long-capture-reconnect-20261014.md。遵循安装规范，复用固定同一候选。

| 检查项 | 结果 | 证据/边界 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.24-54-trial/LibreShot-1.3.24-54.dmg`；1.3.24 build54；e7779fc；DMG SHA256 70574cbf2e41a6a17426191ce85f1e006e4c7207d2cfb5d0a4d08662439504c1 |
| DMG、主程序/helper签名、安装内容一致 | 通过 | package/install --plan/install退出0，通用架构/ad-hoc；安装与候选可执行文件SHA256同为3cc21ef3203ee159973981f7109e070a47ee2e87e67021065406d677af7fe6b6；build.log、SOURCE.json、INSTALL.json |
| 退出旧实例、清理与进程身份 | 通过 | 正常菜单退出后status none；固定/Applications/LibreShot.app；旧安装、旧候选与archive移入废纸篓，retired-apps.json；偏好备份pre-upgrade-preferences.plist |
| 屏幕录制与精确路径 | 通过 | 新包实际报缺失后正常退出；系统UI选择LibreShot旧条目移除，确认消失；+添加/Applications/LibreShot.app，URL和1.3.24预览核对正确，列表on；重启前后真实截图成功 |
| 输入监控及Option | 通过 | 应用退出时单独移除旧输入条目，确认无项目；+添加当前完整路径，1.3.24核对正确且on；重启后缺失提示消失，Option仍1；用户确认本包实体双击Option出现遮罩并按Esc取消正常 |
| 重启前遮罩、标注、保存、剪贴板 | 通过 | `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 09.08.24.png`；470×220公开中英文字和红色圆角矩形，内容可解码；剪贴板PNG字节一致；before-restart.png |
| 同包重启后截图保存 | 通过 | 正常菜单退出、status无进程、Finder同路径重开；`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 09.09.13.png`；470×220公开文字和画笔，剪贴板字节一致；after-restart.png，无再次授权提示 |
| OCR helper | 通过 | 最终包真实公开区域识别五行中英文字，ocr-result.txt；首行0为O，非准确率专项 |
| 原设置保留 | 通过 | 17项语义一致，包含保存书签、自动保存、Option、登录启动、工具设置/样式、快捷键、左键动作和辅助线；settings-preservation.json |
| 公开窗口实际长图 | 有限通过／存在暂时失败 | 最终545×837，ROW000–020连续、无可见重复或跳行，public-long.png，原文件`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 09.19.10.png`。仅一次小步滚动及回访，不能代替用户原页面和复杂长图验收 |
| 修复范围 | 源码通过／用户原场景待试用 | 已证明并修复一种宽度受限的局部重绘误拒绝；没有用户原始帧，不能声称两次现场失败全部由此造成，或所有“未接上”已解决 |
| 最终交付、发布与回退 | 基础验收通过 | 可以测试此修复试用版；新版正常Finder启动并运行。Option实体触发已由用户确认通过；未推送、未发布、未回复Issue。旧DMG/废纸篓可回退，回退须复验 |

## 长截图实测与剩余问题

公开AppKit滚动fixture（源码与应用在dist/long-capture-reconnect-20261014/）包含120行公共编号。选区545×715，排除标题和滚动条。第一次工具滚动后暂时未接上，结束报unstableFinish，未产生长图。第二次对同包只以LaunchServices完整路径加LIBRESHOT_LONG_CAPTURE_TRACE=1启动数值诊断，未重新签名或构建，没有更改全局环境或权限。日志public-long-trace.log仅数字与拒绝原因，无用户帧。

第二次初期出现原像素接缝拒绝（候选122px、约96.5%灰度置信度），随后重新前台激活/确定滚动位置时以122px、100%候选和原像素接缝验证恢复；回访120px不重复追加。最后3个收尾观察帧成功稳定，进入编辑器并保存545×837。当前无法区分工具合成滚动、公开fixture重绘和实际SCK显示变化造成的暂时失败，保留为未解决边界，未放宽接缝校验，也未仅隐藏警告。主场景仍需维护者原应用/页面试用确认。

测试结束正常退出诊断进程，再由Finder完整安装路径重开，无诊断环境；公开fixture已退出。基础前后保存证据来自正常启动，不借用旧包或Preview。窗口关闭后native pipe closed/noWindowsAvailable按真实新PNG及内容确认保存，不作为应用失败。

维护者补充实际场景：当前Codex聊天滚到最上面后开始长截图。继续针对该场景复查，公开fixture不替代此验证。

## 原 Codex 场景复测限制

维护者已确认本包实体双击Option及Esc正常。实际问题场景为当前Codex聊天滚到最上方后开始长截图。桌面工具拒绝访问com.openai.codex；使用此前获授权的AppleScript核对实际宿主ChatGPT窗口，其可访问性树只暴露嵌套AXGroup，没有聊天滚动控件，无法构造可靠的自动化原场景复测。没有保存私人聊天截图，也未将公开fixture结果标作原场景通过。当前最终包保持1.3.24 build54，原场景须维护者实测，记录警告是否随停滚恢复、最后能否完成导出。

## 2026-10-14 下午公开滚动界面交叉测试

维护者要求继续使用可滚动公开界面自行验收。本轮沿用最终安装1.3.24 build54，未重建/重签名主应用；仅用完整路径LaunchServices和进程环境LIBRESHOT_LONG_CAPTURE_TRACE=1打开数值诊断。新增公开WKWebView测试窗口，不加载网络，120行唯一公共编号，源码public-web-long-fixture.swift与可启动.app存放dist/long-capture-reconnect-20261014/。

- AppKit窗口：545×715选区，初始滚轮0.15页约122px触发持续original-pixel-seam-rejected。仅前台激活没有恢复；改用AX滚动条后恢复。在360、720、1080、1440、回访1320、1800、2160px逐步采集，回访时高度保持2155px，最终8个接受帧导出545×2875。原文件/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 14.06.22.png；continuous-2875.png。Vision OCR行号000–071恰好各一次且有序，人工查看公开PNG无可见断行/重复；这不是逐像素完整性证明。
- 第二轮AppKit滚轮：同样122px误接缝拒绝；移出鼠标后灰度候选置信度由约96.5%升至100%，但原像素接缝仍拒绝。同一AX滚动条值0.03034825870646766重设后恢复2帧/837px，取消本轮，不保存失败前缀。与渲染/工具相关，但没有保存拒绝的原始流帧，不能确定其像素根因。
- WKWebView：同样区域内滚轮0.3页约244px持续拒绝。工具键盘动作后AX滚动位置回到0，存在自动化行为不一致；不能把这条异常作为产品键盘滚动缺陷。改用网页AX滚动条0.06、0.12、0.18、0.24、0.30逐步接受，最终6个接受帧、545×1928成功收尾并保存。原文件/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 14.20.46.png；web-1928.png。OCR行号000–047恰好各一次且有序，人工查看无可见跳行/重复。

数值诊断进程79802，continuous-trace.log与scroll-crosscheck-trace.log存放dist/long-capture-reconnect-20261014/，只包含原因/尺寸/位移/置信度。本轮说明多段滚动、短距离回访和成功收尾可以工作，也建立了公开窗口中的可复现拒绝；仍不能宣称所有“未接上”修复。未放宽原像素接缝验证，未修改生产源码，未发布。测试后退出诊断实例，Finder完整路径恢复正常启动，避免留下诊断环境。
