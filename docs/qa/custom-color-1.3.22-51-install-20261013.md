# 自定义颜色入口：1.3.22 build 51 本机验收

2026-10-13。按 `docs/operations/install-and-permissions.md` 执行。最终源码 `c3c9718e49cfd2605a4892b626f457d78fbddf36`，之后只补充外部 QA 文档，没有改变应用签名。此前 build 50 安装实测发现颜色面板被遮罩挡住，因此未交付；最终固定 build 51。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.22-51-trial/LibreShot-1.3.22-51.dmg`；1.3.22 / 51；DMG SHA-256 `d7b610cbc49989ce06353a8320166fc1f3b7d6030b9a2ec185c188dc7e040b60` |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | 固定脚本 package、install --plan、install 均退出 0；通用架构、ad-hoc 签名；候选及安装可执行文件同为 `e5d798f27cdc74ee808c1603a594542625a2efd25d4a4c3e8320847ede2eecbe`；build.log、INSTALL.json |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 原生菜单正常退出后 status 无主进程；旧应用及旧候选移入废纸篓，清单 retired-apps.json；偏好备份 pre-upgrade-preferences.plist；最终 PID 94188 来自 /Applications/LibreShot.app/Contents/MacOS/LibreShot |
| 屏幕录制记录处理方式及精确路径 | 通过 | build 51 实际报录屏缺失，退出后移除旧项目、确认消失，用 + 添加 /Applications/LibreShot.app，选择面板核对 URL/1.3.22，开关 on；重新启动后真实遮罩/截图通过 |
| 输入监控状态、Option 原有开关及实体触发 | 通过 | 同样退出后精确移除、添加最终路径，开关 on；新版快捷键页缺失提示消失，Option 开关仍为 1；用户确认本包双击 Option 出现遮罩并按 Esc 取消正常 |
| 重启前遮罩、截图文件、保存目录、剪贴板 | 通过 | 原目录 `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-13 12.53.01.png`；470×220 公开中英文字加蓝色矩形，可解码；before-restart.png；剪贴板 PNG 字节与保存文件相等 |
| 同包重启后遮罩与保存文件 | 通过 | 正常菜单退出，status 无进程，Finder 同安装路径重开；`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-13 12.59.07.png`，470×220 公开中英文字加红色画笔；after-restart.png；剪贴板字节相等，无再次授权提示 |
| 本次功能验收 | 通过 | 红绿蓝旁调色盘图标点击后 Colors 面板在遮罩上方可见；RGB 输入 #8E44AD 后面板及属性栏均显示对应颜色；关闭面板返回编辑正常。原先被遮挡的场景新增回归先失败后通过；完整属性回归通过，日志 color-layer-*.log |
| 原用户设置 | 通过 | 保存书签、自动保存、Option、登录启动、工具顺序/隐藏项、默认工具、对齐、工具样式、三组快捷键、左键行为和辅助线共 17 项语义一致；样式 JSON 顺序变化不算设置变化；settings-preservation.json |
| OCR helper 实际调用 | 通过 | 同安装包框选公开文字，识别窗口返回五行中英文字；ocr-result.txt；首行数字 0 被识别为 O，链路成功，非字符准确率专项 |
| 最终交付、发布/回退 | 基础验收通过 | 可以测试调色盘入口。当前新版保持运行，公开 fixture 已退出；Option 实体触发已由用户确认通过。未发布、未推送、未回复 Issue，保留旧 DMG/废纸篓可回退，回退须重新验收 |

本包仅验证当前 macOS 和显示配置；浅/深色、窄宽布局源码回归记录见 custom-color-icon-20261013.md。基础结果不借用旧包或 Preview。原生桌面工具关闭截图窗口后偶发 native pipe closed，实际成功通过新 PNG、内容和剪贴板核对确认；菜单、授权与 OCR 读取使用用户此前明确批准的 AppleScript/System Events。
