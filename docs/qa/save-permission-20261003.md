# 默认自动保存目录授权验证（2026-10-03）

## 根因与修复

完整预览版实际框选、复制成功，但默认 Pictures 写盘报 NSCocoaErrorDomain 513。默认目录 URL 不提供沙盒访问授权；此前没有 security-scoped bookmark。另存为通过，图片编码并非这次失败的原因。

仅在写入权限错误时打开目录选择面板，记住所选目录的 security-scoped bookmark，并使用同一份 PNG 重试一次。后续自动保存及重启后使用已选目录。取消选择保留剪贴板，不再包成保存失败弹窗；磁盘满等其他错误仍正常报告。没有增加 Pictures 全目录 entitlement。应用菜单增加“区域截图”，复用已有区域截图入口，便于连续原生流程验收。

## 已完成验证

- 修改前默认权限失败回归为红（513）；修改后 6 组授权恢复回归通过，包括取消、非权限错误、不无限重试、失效旧目录、禁用自动保存、后台写盘及不重复编码。
- 原截图回归 24 项、工具栏回归 26 项通过，总计 56 项。
- 独立真实沙盒程序使用生产 CaptureService、SettingsService 和 NSOpenPanel，只有 sandbox 与 user-selected read-write 权限；使用公开生成的图片，不申请录屏权限。
- 首次启动没有书签，实际选择测试目录后连续保存 2 张，文件 PNG 与剪贴板一致，TIFF 存在。
- 重启同一签名程序，已有目录书签自动生效，再保存 2 张，无需重新选择目录。
- 原始证据：`dist/save-permission-20261003/` 下 red/green 回归日志、sandbox-first-launch.json 与 sandbox-second-launch.json；4 个 PNG 在 sandbox-exports 中。

完整应用新预览已构建并完成 30 次真实区域截图、矩形标注、复制及自动保存。首次权限错误打开生产目录选择面板，确认默认 `/Users/allen/Pictures` 后当前截图保存成功；其后 29 次无目录授权弹窗。30 张 PNG 均能解码且尺寸为 600×940，最后一张 PNG 与剪贴板完全一致，TIFF 尺寸相同，剪贴板为单图片条目。重启同一签名预览后第 31 次截图也直接保存，文件与剪贴板 PNG 一致，TIFF 与单图片条目校验通过；不据此关闭 Issue #5。

## 复现入口

```sh
bash tests/run-save-permission-checks.sh
bash tests/build-save-permission-sandbox-qa.sh dist/save-permission-manual-qa
```

打开生成的 LibreShot Save QA.app，首次选择测试目录，等待程序退出；再次打开同一个包。报告在 `~/Library/Containers/com.allensong.LibreShot.SavePermissionQA.October3/Data/Library/Application Support/LibreShotSaveQA/result.json`。第二次应 `hadBookmarkAtLaunch=true`、`passed=true`。要验证首次启动，使用新的测试 bundle identifier/container；重签名同一 identifier 可能改变 ad-hoc 的书签身份，不等同于同一签名重启。

## 完整预览构建

源提交 `acf0a60`，Release arm64/x86_64 构建、双架构和沙盒签名检查通过。包位于 `dist/LibreShot-Issue9-Preview-20261003-save-permission/LibreShot Preview.app`。录屏授权仍受 ad-hoc 签名变更影响：单纯刷新路径并重启未通过，系统一度重新打开旧包。停止旧测试实例后，使用系统 `tccutil reset ScreenCapture com.allensong.LibreShot.Preview.Issue9` 仅重置预览身份，核对列表无预览项，再添加新包准确路径；新实例 PID 13251 实际截图通过。正式 LibreShot 和其他应用的权限保留。此流程不是稳定发行签名的替代。

完整应用导出、文件清单、PNG/TIFF 校验及 vmmap 原始记录在 `dist/live-memory-20261003/save-recovery/`。公开页面的本地浏览器打开被工具协议策略拦截，未绕过；本轮实际使用已有公开验收文档，截图只包含其正文。

## 完整应用内存与收尾

PID 13251 的框选样例为公开验收文档 600×940 Retina 像素，包含矩形标注。测试前已做两次取消遮罩，采样基线 61.1 MiB，不是冷启动值。首次目录选择并保存后 68.5 MiB；第 10、20、30 次后分别 71.8、72.0、72.2 MiB，峰值 141.5 MiB；第 30 次完成后约 82 秒闲置采样为 48.3 MiB。此样例未见明显持续驻留增长，不覆盖大屏复杂图、长截图、OCR 或约 10 MB 冷启动目标。一次桌面外部交互打断未提交选区，取消后重做，实际文件数与成功操作数一致。

同一签名完整预览重启到 PID 24364，第 31 张保存成功，无目录或录屏重新授权要求。恢复自动保存关闭；保存目录仍为 Pictures，保留本次取得的书签。31 张测试生成文件已按清单逐个校验 SHA256 后移至可恢复的废纸篓子目录 `~/.Trash/LibreShot-QA-20261003-1132-1139`，证据副本保留在 dist。正式应用未替换，未推送或发布。OCR 首次使用高驻留、Intel 实机、多屏及正式签名升级仍待验证。
