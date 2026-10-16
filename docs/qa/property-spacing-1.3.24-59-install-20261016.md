# 1.3.24 build 59 本机换包

2026-10-16。按安装规范打包并替换 `/Applications/LibreShot.app`。DMG 对应源码 `8cc4011`（相对 `a0f8ed0` 的 `source.patch` 与该提交一致）。这一包包含文字清晰度、画笔不可拖动、色盘开关、属性栏间隔，以及已在构建号 56 确认的长截图远程边框。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `dist/LibreShot-1.3.24-59-property-spacing/LibreShot-1.3.24-59.dmg`；1.3.24 / 59；SHA256 `7207df7f2a913331ecf1323535d7f7b42bec059638c0140fc1e8b3a79c4f4eb3` |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | package、install --plan、install 退出 0；ad-hoc 通用架构 |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 正常退出后 status 无主进程；构建号 58 的应用副本移入废纸篓；最终进程来自 `/Applications/LibreShot.app/Contents/MacOS/LibreShot`，版本 1.3.24 build 59 |
| 屏幕录制记录处理方式及精确路径 | 通过 | 维护者用最终安装的 `/Applications/LibreShot.app`（1.3.24 build 59）完成截图；未再要求重新授权 |
| 重启前遮罩、截图文件、保存目录、剪贴板 | 通过 | 维护者确认同包截图保存通过。保存目录中可见 `~/Downloads/Screenshot 2026-10-16 16.35.22.png`（1126×296）、`16.35.35.png`（1084×260） |
| 同包重启后遮罩与保存文件 | 通过 | 维护者确认退出重开后截图仍通过。同目录可见 `Screenshot 2026-10-16 17.30.12.png`（1264×659）、`17.30.28.png`（1564×522）、`17.30.33.png`（1533×542）。未做剪贴板逐像素对照 |
| 属性栏色点与字号不再重叠 | 通过 | 维护者查看构建号 59 后确认间隔好很多，色点不再压住「字号」 |
| 输入监控状态、Option 原有开关及实体触发 | 未在本包复测 | 构建号 56 曾通过；不把旧包结果当作本包通过 |
| 长截图远程边框 | 包含源码，本包未复测 | 构建号 56 由维护者在远程桌面确认；构建号 59 含该改动 |
| 最终交付状态、发布/回退状态 | 已发布 v1.3.24 | [Release](https://github.com/songpl-AI/LibreShot/releases/tag/v1.3.24)。重新下载的 DMG SHA-256 仍为 `7207df7f2a913331ecf1323535d7f7b42bec059638c0140fc1e8b3a79c4f4eb3`，与原包一致。资产：`LibreShot-1.3.24-59.dmg`、`SHA256SUMS`、`INSTALL-AND-PERMISSIONS.md`。标签指向 `c0d83a5`，构建源码为 `8cc4011`。回退可用废纸篓中的构建号 58 副本 |

## 发布后的 Issue

- [#41](https://github.com/songpl-AI/LibreShot/issues/41#issuecomment-6212571444) 已回复并关闭。
- [#38](https://github.com/songpl-AI/LibreShot/issues/38#issuecomment-6212572274) 已回复并关闭。该行为来自 v1.3.23。
- [#40](https://github.com/songpl-AI/LibreShot/issues/40#issuecomment-6212573096) 已回复画笔、调色板和属性栏；其余意见保持开放。
- [#33](https://github.com/songpl-AI/LibreShot/issues/33)、[#34](https://github.com/songpl-AI/LibreShot/issues/34) 早前已在 v1.3.19 回复，本次关闭。
- 仍开放：[#40](https://github.com/songpl-AI/LibreShot/issues/40)、[#39](https://github.com/songpl-AI/LibreShot/issues/39)、[#37](https://github.com/songpl-AI/LibreShot/issues/37)、[#36](https://github.com/songpl-AI/LibreShot/issues/36)、[#35](https://github.com/songpl-AI/LibreShot/issues/35)、[#32](https://github.com/songpl-AI/LibreShot/issues/32)、[#27](https://github.com/songpl-AI/LibreShot/issues/27)、[#20](https://github.com/songpl-AI/LibreShot/issues/20)。#32 的滚轮已在 v1.3.19 完成，右上角关闭按钮仍未做，所以保持开放。
