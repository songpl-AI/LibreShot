# 1.3.24 build 63 本机换包

2026-10-16。按安装规范打包并替换 `/Applications/LibreShot.app`。基线源码 `fc32118`，放大镜改动尚未提交，记录在包内 `source.patch`。这一包修正放大预览的上下方向，使十字周围的内容和屏幕一致。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `dist/LibreShot-1.3.24-63-loupe-orientation/LibreShot-1.3.24-63.dmg`；1.3.24 / 63；SHA256 `1e82bb305f6795c1569736ce776b2bd0bdebacc3566827e3dd80eab2312b1d1f` |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | package、install --plan、install 退出 0；ad-hoc 通用架构 |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 正常退出后 status 无主进程；构建号 62 的应用副本移入废纸篓；最终进程来自 `/Applications/LibreShot.app/Contents/MacOS/LibreShot`，版本 1.3.24 build 63 |
| 屏幕录制记录处理方式及精确路径 | 待验 | 新 ad-hoc 身份可能使旧授权失效；尚未用本包实际截图 |
| 输入监控状态、Option 原有开关及实体触发 | 待验 | 未在本包实测 |
| 重启前遮罩、截图文件、保存目录、剪贴板 | 待验 | 未保存本包截图 |
| 同包重启后遮罩与保存文件 | 待验 | 未做同包重启后的第二次保存 |
| 放大预览方向与指针一致 | 通过 | 维护者在构建号 63 上实际框选，确认放大内容与十字位置一致，左下方预览和拾色可用 |
| 最终交付状态、发布/回退状态 | 已发布 v1.3.25 | [Release](https://github.com/songpl-AI/LibreShot/releases/tag/v1.3.25)。重新下载的 DMG SHA-256 仍为 `1e82bb305f6795c1569736ce776b2bd0bdebacc3566827e3dd80eab2312b1d1f`。资产：`LibreShot-1.3.24-63.dmg`、`SHA256SUMS`、`INSTALL-AND-PERMISSIONS.md`。标签在文档提交上，构建源码为 `89974f1`。安装后显示 1.3.24（63）。同包重启前后保存未单独记录。回退可用废纸篓中的构建号 62 副本 |

## 发布后的 Issue

- [#37](https://github.com/songpl-AI/LibreShot/issues/37#issuecomment-6213586028) 已回复并关闭。框选时提供放大、坐标和颜色复制，不是独立取色工具。
- 仍开放：[#40](https://github.com/songpl-AI/LibreShot/issues/40)、[#39](https://github.com/songpl-AI/LibreShot/issues/39)、[#36](https://github.com/songpl-AI/LibreShot/issues/36)、[#35](https://github.com/songpl-AI/LibreShot/issues/35)、[#32](https://github.com/songpl-AI/LibreShot/issues/32)、[#27](https://github.com/songpl-AI/LibreShot/issues/27)、[#20](https://github.com/songpl-AI/LibreShot/issues/20)。
