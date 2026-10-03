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

独立沙盒通过不能代替完整应用新构建的重复截图、标注与内存测量。完整应用验证待新预览构建和录屏授权匹配后进行；不据此关闭 Issue #5。

## 复现入口

```sh
bash tests/run-save-permission-checks.sh
bash tests/build-save-permission-sandbox-qa.sh dist/save-permission-manual-qa
```

打开生成的 LibreShot Save QA.app，首次选择测试目录，等待程序退出；再次打开同一个包。报告在 `~/Library/Containers/com.allensong.LibreShot.SavePermissionQA.October3/Data/Library/Application Support/LibreShotSaveQA/result.json`。第二次应 `hadBookmarkAtLaunch=true`、`passed=true`。要验证首次启动，使用新的测试 bundle identifier/container；重签名同一 identifier 可能改变 ad-hoc 的书签身份，不等同于同一签名重启。
