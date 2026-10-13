# 最新主线 1.3.23 build 53 本机验收

2026-10-14，按安装与授权规范执行。fetch origin后当前分支从26166f4快进到1598d85c1ed1b3aa7f157e7fa03f952bbe45b7ca，无冲突。原有未跟踪docs/marketing/与issue20-memory-20261008.md保持不动。远端已设置build53，未另改生产源码；从干净临时worktree按固定脚本打包，QA提交晚于构建，不改变签名。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.23-53-trial/LibreShot-1.3.23-53.dmg`；1.3.23 build53；源码1598d85；DMG SHA256 d8efbe4b7addcdd382cf295fe470b500b595dca36235a329ff368e3592921675；SOURCE.json、SHA256SUMS |
| DMG、主应用/helper签名、安装内容一致 | 通过 | 固定package、install --plan、install退出0，通用架构/ad-hoc校验通过，build.log；安装与候选可执行文件同SHA256 f8078c108bc3219fb5214b5f2b58173bff3d9fcfeefab985000699a157f603df |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 菜单正常退出后status none；旧副本移入废纸篓，retired-apps.json；pre-upgrade-preferences.plist；最终PID32061来自/Applications/LibreShot.app/Contents/MacOS/LibreShot |
| 屏幕录制处理及路径 | 通过 | 新包实际报缺失；退出后准备刷新授权，用户随后确认已全部替换为最新副本。最终从/Applications/LibreShot.app重新启动，真实遮罩、标注及重启前后PNG成功；无再次授权提示 |
| 输入监控状态、Option开关及实体触发 | 通过 | 用户确认已刷新最新权限；新版缺失提示消失，Option仍为1。用户确认本包双击Option出现遮罩并按Esc取消正常，未借用旧包结果 |
| 重启前遮罩、保存目录、文件、剪贴板 | 通过 | `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 07.39.13.png`；940×440公开中英文字加红色圆角矩形，图片可解码；剪贴板PNG字节一致；before-restart.png |
| 同包重启后遮罩、保存、剪贴板 | 通过 | 正常菜单退出、status无进程、Finder同安装路径重开；`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-14 07.40.08.png`，940×440公开文字加红色画笔；剪贴板字节一致；after-restart.png |
| OCR helper实际调用 | 通过 | 同安装副本框选公开文字，返回五行中英文字，ocr-result.txt；首行0识别为O，不作为字符准确率专项 |
| 原用户设置 | 通过 | 保存书签、自动保存、Option、登录启动、工具配置/样式、快捷键、左键行为、辅助线共17项语义一致，settings-preservation.json |
| 本次新增改动及环境边界 | 基础通过／专项待用户试用 | 基础区域截图、矩形/画笔、PNG/剪贴板/OCR通过；本次主线合入长截图与内存生命周期实现，未重复完整长截图、翻译、贴图内存专项；不能据此宣称这些专项全部通过 |
| 最终交付、发布/回退 | 基础验收通过 | 可以测试本次主线改动；新版保持运行，公开fixture已退出。Option实体触发已由用户确认通过；本次未推送/发布/回复Issue，原已发布build52不被替换。旧DMG和废纸篓可回退，回退须复验 |

## 桌面工具定位修正

今天窗口落在Retina主屏（1512×982逻辑点，截图3024×1964像素）。首次复用1×坐标产生40×181误选区，存为invalid-coordinate-attempt.png并排除验收。对照实际选区后使用2×截图像素坐标，重新框选470×220逻辑点得到正确940×440PNG；再正常重启后重复成功，未修改应用本体。OCR首次前台显示器切换得到非fixture结果，排除并不保留文本；重新在外接屏确认公开窗口后识别通过。工具关闭窗口后偶发native pipe closed，以最终文件、内容和剪贴板核对成功。菜单、定位及结果读取使用此前用户批准的AppleScript/System Events。
