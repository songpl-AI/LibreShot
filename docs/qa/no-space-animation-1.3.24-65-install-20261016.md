# 1.3.24 build 65 本机换包

2026-10-16。按安装规范打包并替换 `/Applications/LibreShot.app`。去掉 `canJoinAllApplications` 的改动尚未提交，记录在包内 `source.patch`。这一包撤回构建号 64 的全屏空间请求，开始截图时不再触发系统空间动画。#39 不宣称已修复。

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | `dist/LibreShot-1.3.24-65-no-space-animation/LibreShot-1.3.24-65.dmg`；1.3.24 / 65；SHA256 `590446819d17c7402a82e5c77b60a2145b1aaa8d1808a79d858e166fd34cee5c` |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | package、install --plan、install 退出 0；ad-hoc 通用架构 |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 正常退出后 status 无主进程；构建号 64 的应用副本移入废纸篓；最终进程来自 `/Applications/LibreShot.app/Contents/MacOS/LibreShot`，版本 1.3.24 build 65 |
| 屏幕录制记录处理方式及精确路径 | 待验 | 新 ad-hoc 身份可能使旧授权失效；尚未用本包实际截图 |
| 输入监控状态、Option 原有开关及实体触发 | 待验 | 未在本包实测 |
| 绿色按钮全屏后区域截图 | 本机通过 | 维护者把 App 点左上角绿色按钮进入系统全屏后，用快捷键可以打开 LibreShot 的区域截图。未在报告人的系统上复测，不宣称 #39 对所有环境已修复 |
| 最终交付状态、发布/回退状态 | 已安装，全屏快捷键已试过 | 不发布。回退可用废纸篓中的构建号 64 副本，恢复后须重新验收 |
