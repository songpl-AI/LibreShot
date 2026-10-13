# 1.3.23 build 52 本机换包验收

2026-10-13。按安装规范执行；最终源码 76255fcf957aa8e3413c7550b08a5ba84359bcc1。之后只补外部 QA 文档，没有重新构建或改签名。修复普通鼠标点击色盘无响应，细化十字辅助线。源码鼠标回归先失败后通过（包括关闭重开），完整属性检查通过；详见 palette-mouse-and-guides-20261013.md。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `/Volumes/ExtremeSSD/AIProject/LibreShot/dist/LibreShot-1.3.23-52-trial/LibreShot-1.3.23-52.dmg`；1.3.23 / 52；SHA256 b49746708a057eb76701367fb8cf56bc37c7bdbbd17087dc9eeef897c4869dc5 |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | package / install --plan / install 全部退出0；通用架构 ad-hoc；候选与安装可执行文件 SHA256 同为 3db6885b0d934bf7e76839cdece035a1c0a0a7c55dfd0ee56b7db52a9d0ba91f |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 正常菜单退出，status确认none；旧应用移入废纸篓，retired-apps.json；pre-upgrade-preferences.plist；最终 PID 97157 来自 /Applications/LibreShot.app/Contents/MacOS/LibreShot |
| 屏幕录制记录处理方式及精确路径 | 通过 | 新包报缺失后正常退出；用户完成系统Touch ID/密码验证；观察旧项目消失，用 + 精确添加 /Applications/LibreShot.app，选择面板URL与版本1.3.23核对正确，开关on；同包重启前后实际截图保存通过 |
| 输入监控状态、Option原有开关及实体触发 | 通过 | 同退出状态移除旧输入条目，确认无项目后添加当前完整路径，开关on；过程中Mac锁定，用户手动解锁后继续。新版快捷键缺失提示消失，Option仍为1；用户确认本包双击Option出现遮罩并按Esc取消正常 |
| 重启前遮罩、截图文件、保存目录、剪贴板 | 通过 | `/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-13 17.11.58.png`；470×220公开中英文字加自定义紫色箭头，图片可解码，剪贴板PNG与文件字节一致；before-restart.png |
| 同包重启后遮罩与保存文件 | 通过 | 正常菜单退出、status无主进程、Finder完整安装路径重开；`/Volumes/ExtremeSSD/Download/ScreenShots/Screenshot 2026-10-13 17.21.31.png`；470×220公开文字加红色画笔，无再次授权提示；剪贴板字节一致，after-restart.png |
| 色盘真实鼠标验收 | 通过 | 普通坐标点击图标中心打开Colors；关闭后再点击重开；矩形切箭头后坐标点击打开。RGB输入#8E44AD后属性栏接收紫色且实际导出紫色箭头；测试后恢复原红色默认值。没有用AX激活替代鼠标验证 |
| 辅助线样式 | 通过 | 真实遮罩看到细半透明短虚线；选区编辑时消失，最终导出无辅助线；源码生产Canvas浅/深背景图片已检查 |
| 原设置保留 | 通过 | 共17项语义一致，包含保存书签、自动保存、Option、登录启动、工具配置与样式、快捷键、左键行为、辅助线；settings-preservation.json |
| OCR实际调用 | 通过 | 最终包框选同公开内容，返回五行中英文字，ocr-result.txt；首行0被识别成O，非字符准确率专项 |
| 最终交付状态、发布/回退状态 | 基础验收通过 | 可测试色盘及辅助线；应用保持运行，公开fixture已退出；Option实体触发已由用户确认通过。未发布、未推送、未回复Issue；旧DMG/废纸篓可用于回退，回退须复验 |

验收始终使用同一最终安装包。工具关闭截图窗口后偶发native pipe closed，重新识别窗口并以真实新文件、解码内容和剪贴板确认结果。菜单/授权/OCR读数使用此前用户明确批准的AppleScript/System Events；未更改其他应用权限。未覆盖其他macOS与显示配置。
