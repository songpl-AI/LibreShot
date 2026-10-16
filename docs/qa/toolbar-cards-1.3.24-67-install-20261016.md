# 1.3.24 build 67 本机换包

2026-10-16。按安装规范打包并替换 `/Applications/LibreShot.app`。缩小工具栏设置卡片的改动尚未提交，记录在包内 `source.patch`。这一包把设置里的工具改成更小的横排卡片，左右顺序与截图工具栏一致。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `dist/LibreShot-1.3.24-67-toolbar-cards/LibreShot-1.3.24-67.dmg`；1.3.24 / 67；SHA256 `916029217f1ccad19c946bd7b26390fd53f343cabc00e268b8dc33753b03be0b` |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | package、install --plan、install 退出 0；ad-hoc 通用架构 |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 正常退出后 status 无主进程；构建号 66 的应用副本移入废纸篓；最终进程来自 `/Applications/LibreShot.app/Contents/MacOS/LibreShot`，版本 1.3.24 build 67 |
| 屏幕录制记录处理方式及精确路径 | 待验 | 新 ad-hoc 身份可能使旧授权失效；尚未用本包实际截图 |
| 工具栏设置小卡片左右滑动 | 待验 | 源码工具栏检查通过；安装副本的设置页尚未实际查看 |
| 最终交付状态、发布/回退状态 | 已安装，授权/验收未完成 | 不发布。回退可用废纸篓中的构建号 66 副本，恢复后须重新验收 |
