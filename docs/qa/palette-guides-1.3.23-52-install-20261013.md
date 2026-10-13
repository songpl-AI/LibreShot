# 1.3.23 build 52 本机换包验收（进行中）

2026-10-13。源码 76255fcf957aa8e3413c7550b08a5ba84359bcc1。修复原生色盘普通鼠标点击无响应，细化十字辅助线；源码鼠标回归先失败后通过，含关闭后重新打开，完整属性检查通过。浅深色生产 Canvas 已渲染检查，见 palette-mouse-and-guides-20261013.md。

| 检查项 | 结果 | 证据/阻塞 |
| --- | --- | --- |
| 包路径、版本/build、源码、SHA-256 | 通过 | dist/LibreShot-1.3.23-52-trial/LibreShot-1.3.23-52.dmg；1.3.23 / 52；SHA256 b49746708a057eb76701367fb8cf56bc37c7bdbbd17087dc9eeef897c4869dc5 |
| DMG、主应用/helper 签名、安装内容一致 | 通过 | 固定 package / install --plan / install 全部退出0；通用架构 ad-hoc；可执行文件SHA256 3db6885b0d934bf7e76839cdece035a1c0a0a7c55dfd0ee56b7db52a9d0ba91f |
| 旧实例退出、备份路径、实际新进程路径 | 通过 | 菜单正常退出，status确认none；固定安装路径/Applications/LibreShot.app；INSTALL.json/retired-apps.json；pre-upgrade-preferences.plist |
| 屏幕录制记录处理方式及精确路径 | 待验 | 新包实际报录屏缺失；正常退出且status确认none后移除旧LibreShot项目，系统弹出Touch ID/密码验证，已请求用户完成。尚未完成移除、添加与复查 |
| 输入监控状态、Option 原有开关及实体触发 | 待验 | 新包快捷键页报缺失；须恢复最终包授权并重新核对。旧包Option结果不替代 |
| 重启前遮罩、截图文件、保存目录、剪贴板 | 待验 | 等待系统验证及授权恢复 |
| 同包重启后遮罩与保存文件 | 待验 | 尚未执行 |
| 本次功能验收、未覆盖环境 | 源码通过／安装待验 | 待以真实鼠标验证首次打开、关闭重开、换工具打开；待查看真实辅助线 |
| 最终交付状态、发布/回退状态 | 已安装，授权/验收未完成 | 应用已退出等待系统验证；不能宣称安装通过或交付测试。未发布/推送，旧DMG和废纸篓保留 |

此前已明确允许AppleScript/System Events fallback，沿用授权；不修改其他应用权限。系统身份验证由用户完成。文档不改变安装包签名。
