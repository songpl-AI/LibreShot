# LibreShot

[中文](README.md) | [English](README_EN.md) · [MIT License](LICENSE)

免费开源的原生 macOS 截图与标注工具。

[下载 v1.3.14](https://github.com/songpl-AI/LibreShot/releases/tag/v1.3.14) · [更新说明](docs/releases/1.3.14.md) · [更新日志](CHANGELOG.md)

## 核心功能

- **区域、全屏与长截图**：全屏截图捕捉鼠标所在屏幕，进入标注；长截图支持滚动、缩放和编辑。
- **标注与工具属性**：画笔、矩形、椭圆、箭头、文字、序号、马赛克和模糊；自动显示属性栏，独立记忆设置，支持恢复默认与撤销。
- **圆角与序号配色**：矩形支持圆角，序号支持实心／描边及边框、填充、数字独立颜色。
- **OCR 与翻译**：本机识别文字，支持文本翻译和原图位置翻译；翻译需 macOS 26+，首次下载语言包需联网。
- **复制、保存与贴图**：新用户默认完成截图仅复制，可开启自动保存；支持手动保存、另存为和贴图置顶。
- **个性化操作**：自定义快捷键、工具栏顺序和默认工具，可选双击 Option 启动截图。

## 安装

支持 **macOS 13+、Apple Silicon 与 Intel**；翻译功能需 macOS 26+。

1. 从 [GitHub Releases](https://github.com/songpl-AI/LibreShot/releases) 下载 DMG。
2. 打开 DMG，将 `LibreShot.app` 拖入“应用程序”；升级前先退出旧版。
3. 首次截图允许“屏幕录制”；使用双击 Option 时还需“输入监控”。

安装包使用 ad-hoc 签名，未经过 Apple 公证；macOS 可能提示阻止打开。安装、校验及升级授权处理见 [安装指南](docs/installation.md)。

## 快速使用

1. 从菜单栏选择区域、全屏或长截图，也可使用快捷键。
2. 框选后点击工具进行标注，属性栏自动显示；矩形圆角在“矩形属性”中调整。
3. 双击选区、按回车或点击 ✅ 完成；新用户默认仅复制。手动保存用 `⌘S`，另存为用 `⌘⇧S`，取消用 `Esc`。

| 操作 | 默认快捷键 |
| --- | --- |
| 区域截图 | `⌘⇧X` |
| 全屏截图 | `⌘⇧A` |

快捷键可在设置中修改；升级保留原设置。详细操作见 [使用指南](docs/usage.md)。

## 文档与反馈

- [使用指南](docs/usage.md)：标注、工具属性、保存、长截图与翻译。
- [安装指南](docs/installation.md)：安装、系统权限与升级问题。
- [开发指南](docs/development.md)：自行构建、打包与测试。
- [提交 Issue](https://github.com/songpl-AI/LibreShot/issues)：反馈问题或建议；也欢迎 Pull Request。

## 支持项目

如果 LibreShot 对你有帮助，欢迎通过 [GitHub Sponsors](https://github.com/sponsors/songpl-AI) 支持维护，或关注公众号。

<img src="docs/wechat.JPG" width="200" alt="公众号二维码">

## 许可证

本项目采用 [MIT License](LICENSE) 开源。

Copyright (c) 2026 Allen
