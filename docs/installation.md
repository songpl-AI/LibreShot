# 安装与升级

[返回 README](../README.md) · [English](installation_EN.md)

## 安装

支持 macOS 13+，安装包同时包含 Apple Silicon 与 Intel 架构；翻译需 macOS 26+。

1. 从 [官方 Release](https://github.com/songpl-AI/LibreShot/releases) 下载 DMG 与 SHA256SUMS。
2. 在两个文件所在目录运行 `shasum -a 256 -c SHA256SUMS` 校验下载。
3. 打开 DMG，将 LibreShot.app 拖入“应用程序”。

安装包采用 ad-hoc 签名，未经过 Apple 公证。若 macOS 阻止打开，按 [Apple 官方指引](https://support.apple.com/zh-cn/102445) 在“系统设置 → 隐私与安全性”中处理。若提示文件损坏，先重新下载并核对校验值；不要全局关闭 Gatekeeper。

## 系统权限

- **屏幕录制／录屏与系统录音**：读取区域、全屏及长截图内容。
- **输入监控**：启用双击 Option 手势时需要。
- **保存目录**：通过应用设置选择目录，授予该目录的文件访问授权。

权限位于“系统设置 → 隐私与安全性”。授权后按系统提示退出并重新打开 LibreShot。

## 升级与权限失效

先正常退出旧版，再替换 `/Applications/LibreShot.app`，原设置和保存目录保留。不同 ad-hoc 构建可能需要刷新已有权限。

如果系统开关已开启，但新版仍提示缺失：

1. 正常退出 LibreShot。
2. 在失效的权限页移除旧 LibreShot 项。
3. 用“+”添加当前 `/Applications/LibreShot.app`，确认条目与开关开启。
4. 从“应用程序”重新打开，完成一次截图与保存；重启应用再检查。

屏幕录制和输入监控分别处理，只刷新失效项。系统身份验证需本人完成。截图正常但无法保存时，从 LibreShot 设置重新选择原保存目录。

## 反馈问题

在 [Issue](https://github.com/songpl-AI/LibreShot/issues) 中注明应用版本与 build、macOS 版本、处理器架构、是否多屏及复现步骤。附图前请遮挡私人内容。

维护者换包与发布流程见 [安装验收规范](operations/install-and-permissions.md)、[固定换包脚本](operations/local-upgrade-script.md) 和 [发布流程](operations/release-and-issue-response.md)。
