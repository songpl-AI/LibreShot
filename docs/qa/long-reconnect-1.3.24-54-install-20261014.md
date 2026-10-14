# 局部重绘修复试用版 1.3.24 build 54

2026-10-14。固定源码e7779fc，包含局部重绘唯一零位移证明；之后只补QA文档，不改应用签名。源码复现与220项优化回归见long-capture-reconnect-20261014.md。遵循安装规范，复用固定同一候选。

| 检查项 | 结果 | 证据/边界 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.24-54-trial/LibreShot-1.3.24-54.dmg`；1.3.24 build54；e7779fc；DMG SHA256 70574cbf2e41a6a17426191ce85f1e006e4c7207d2cfb5d0a4d08662439504c1 |
| DMG、主程序/helper签名、安装内容一致 | 通过 | package/install --plan/install退出0，通用架构/ad-hoc；安装与候选可执行文件SHA256同为3cc21ef3203ee159973981f7109e070a47ee2e87e67021065406d677af7fe6b6；build.log、SOURCE.json、INSTALL.json |
| 退出旧实例、清理与进程身份 | 通过 | 正常菜单退出后status none；固定/Applications/LibreShot.app；旧安装、旧候选与archive移入废纸篓，retired-apps.json；偏好备份pre-upgrade-preferences.plist |
| 屏幕录制与精确路径 | 通过 | 新包实际报缺失后正常退出；系统UI选择LibreShot旧条目移除，确认消失；+添加/Applications/LibreShot.app，URL和1.3.24预览核对正确，列表on；重启前后真实截图成功 |
| 输入监控及Option | 状态通过／实体待验 | 应用退出时单独移除旧输入条目，确认无项目；+添加当前完整路径，1.3.24核对正确且on；重启后缺失提示消失，Option仍1；已请求用户本包实体双击Option与Esc确认，尚未收到 |
| 重启前遮罩、标注、保存、剪贴板 | 通过 | `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 09.08.24.png`；470×220公开中英文字和红色圆角矩形，内容可解码；剪贴板PNG字节一致；before-restart.png |
| 同包重启后截图保存 | 通过 | 正常菜单退出、status无进程、Finder同路径重开；`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 09.09.13.png`；470×220公开文字和画笔，剪贴板字节一致；after-restart.png，无再次授权提示 |
| OCR helper | 通过 | 最终包真实公开区域识别五行中英文字，ocr-result.txt；首行0为O，非准确率专项 |
| 原设置保留 | 通过 | 17项语义一致，包含保存书签、自动保存、Option、登录启动、工具设置/样式、快捷键、左键动作和辅助线；settings-preservation.json |
| 公开窗口实际长图 | 有限通过／存在暂时失败 | 最终545×837，ROW000–020连续、无可见重复或跳行，public-long.png，原文件`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 09.19.10.png`。仅一次小步滚动及回访，不能代替用户原页面和复杂长图验收 |
| 修复范围 | 源码通过／用户原场景待试用 | 已证明并修复一种宽度受限的局部重绘误拒绝；没有用户原始帧，不能声称两次现场失败全部由此造成，或所有“未接上”已解决 |
| 最终交付、发布与回退 | 基础验收通过 | 可以测试此修复试用版；新版正常Finder启动并运行。Option实体待验单列；未推送、未发布、未回复Issue。旧DMG/废纸篓可回退，回退须复验 |

## 长截图实测与剩余问题

公开AppKit滚动fixture（源码与应用在dist/long-capture-reconnect-20261014/）包含120行公共编号。选区545×715，排除标题和滚动条。第一次工具滚动后暂时未接上，结束报unstableFinish，未产生长图。第二次对同包只以LaunchServices完整路径加LIBRESHOT_LONG_CAPTURE_TRACE=1启动数值诊断，未重新签名或构建，没有更改全局环境或权限。日志public-long-trace.log仅数字与拒绝原因，无用户帧。

第二次初期出现原像素接缝拒绝（候选122px、约96.5%灰度置信度），随后重新前台激活/确定滚动位置时以122px、100%候选和原像素接缝验证恢复；回访120px不重复追加。最后3个收尾观察帧成功稳定，进入编辑器并保存545×837。当前无法区分工具合成滚动、公开fixture重绘和实际SCK显示变化造成的暂时失败，保留为未解决边界，未放宽接缝校验，也未仅隐藏警告。主场景仍需维护者原应用/页面试用确认。

测试结束正常退出诊断进程，再由Finder完整安装路径重开，无诊断环境；公开fixture已退出。基础前后保存证据来自正常启动，不借用旧包或Preview。窗口关闭后native pipe closed/noWindowsAvailable按真实新PNG及内容确认保存，不作为应用失败。
