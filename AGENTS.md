# 项目操作规则

构建新试用包、替换本机应用、恢复授权或准备 GitHub Release 时，必须先阅读并逐项执行 [新包安装与授权验收规范](docs/operations/install-and-permissions.md)。每包填写版本 QA 清单；只有最终安装副本在同包重启前后均实际截图、保存成功，才能宣称安装验收通过或交给用户测试新功能。输入监控与屏幕录制分别验收，旧包/Preview 结果不替代新包。

本地试用包校验通过后，直接用 `scripts/upgrade_local.py install <包目录>` 替换 `/Applications/LibreShot.app`。脚本将旧版移入废纸篓并校验安装副本。随后从该路径启动新版，分别检查录屏和输入监控，只恢复实际失效的权限。

失效权限通过 [LibreShot 本机权限恢复](LOOPS.md#libreshot-本机权限恢复) 执行。代理负责权限页面与文件选择器的操作，包括确认「打开」。系统要求密码或 Touch ID 时交给用户，用户确认后从当前界面继续。授权后完成同包重启前后的截图保存和本次改动的专项验收，优先使用终端和针对性脚本。

发布 GitHub Release 或回复相关 Issue 时，必须先执行 [发布与 Issue 回复流程](docs/operations/release-and-issue-response.md)，核对原验收包、公开下载校验和回复范围。
