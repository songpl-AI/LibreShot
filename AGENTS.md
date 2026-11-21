# 项目操作规则

构建新试用包、替换本机应用、恢复授权或准备 GitHub Release 时，必须先阅读并逐项执行 [新包安装与授权验收规范](docs/operations/install-and-permissions.md)。每包填写版本 QA 清单；只有最终安装副本在同包重启前后均实际截图、保存成功，才能宣称安装验收通过或交给用户测试新功能。输入监控与屏幕录制分别验收，旧包/Preview 结果不替代新包。

本地试用包校验通过后，直接用 `scripts/upgrade_local.py install <包目录>` 替换 `/Applications/LibreShot.app`，由脚本将旧版移入废纸篓并校验安装文件。换包完成后立即交接给用户，由用户打开新版并按需处理录屏、输入监控等系统授权。收到用户确认后再继续验收和后续开发。本流程通过终端脚本和用户实测完成，禁用 Computer Use。

发布 GitHub Release 或回复相关 Issue 时，必须先执行 [发布与 Issue 回复流程](docs/operations/release-and-issue-response.md)，核对原验收包、公开下载校验和回复范围。
