# 项目操作规则

构建新试用包、替换本机应用、恢复授权或准备 GitHub Release 时，必须先阅读并逐项执行 [新包安装与授权验收规范](docs/operations/install-and-permissions.md)。每包填写版本 QA 清单；只有最终安装副本在同包重启前后均实际截图、保存成功，才能宣称安装验收通过或交给用户测试新功能。输入监控与屏幕录制分别验收，旧包/Preview 结果不替代新包。

本地试用包校验通过后，直接用 `scripts/upgrade_local.py install <包目录>` 替换 `/Applications/LibreShot.app`。脚本将旧版移入废纸篓并校验安装副本。随后从该路径启动新版，分别检查录屏和输入监控，只恢复实际失效的权限。

权限界面按安装验收规范第 3 节执行。使用 Computer Use 按控件名称和状态批量完成可确认的步骤，每次核对当前权限页、LibreShot 条目和新版路径。界面不符或出现密码、Touch ID 等身份验证时立即停在当前页面并通知用户。收到用户确认后，从当前页面核对实际结果并继续，无需重复已完成的步骤。授权后完成同包重启前后的截图保存和本次改动的专项验收，优先使用终端和针对性脚本。

发布 GitHub Release 或回复相关 Issue 时，必须先执行 [发布与 Issue 回复流程](docs/operations/release-and-issue-response.md)，核对原验收包、公开下载校验和回复范围。
