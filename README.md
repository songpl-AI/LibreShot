# LibreShot

LibreShot 是一款轻量、现代化的 macOS 截图与标注工具。

## ✨ 特性

- **极简设计**：原生 macOS 风格，轻量快速。
- **标注功能**：支持矩形、箭头、文字等多种标注工具。
- **贴图置顶**：支持将截图“贴”在屏幕最上层，方便对照参考。
- **快捷键支持**：全键盘操作，效率倍增。
- **隐私安全**：完全离线运行，不上传任何数据。
- **完全免费**：开源自由，打破收费壁垒。

## 📦 安装

### 方式一：GitHub Releases (推荐)

1. 前往 [Releases](https://github.com/songpl-AI/LibreShot/releases) 页面下载最新的 `.dmg` 安装包。
2. 双击打开 `.dmg` 文件，将 `LibreShot.app` 拖入 `Applications` 文件夹。

> ⚠️ **注意：首次打开如遇“无法验证开发者”**
> 
> 由于本项目未购买 Apple 开发者证书（每年 $99），macOS 可能会拦截运行。请按以下步骤操作（仅需一次）：
> 1. 在“应用程序”文件夹中找到 LibreShot。
> 2. **右键点击** (或按住 Control 点击) 应用图标。
> 3. 选择菜单中的 **“打开”**。
> 4. 在弹出的警告框中点击 **“打开”**。

如果仍然提示“文件已损坏”，请在终端运行以下命令修复：
```bash
xattr -cr /Applications/LibreShot.app
```

### 方式二：自行构建

```bash
git clone https://github.com/songpl-AI/LibreShot.git
open LibreShot.xcodeproj
# 使用 Xcode 编译并运行
```

## ❤️ 赞助与支持

LibreShot 是一个免费开源项目。如果您觉得它提高了您的工作效率，欢迎请作者喝杯咖啡，这将鼓励我继续维护和更新！

| 微信支付 | 支付宝 |
| :---: | :---: |
| <img src="docs/wechat_pay.jpg" width="200" alt="WeChat Pay"> | <img src="docs/alipay.jpg" width="200" alt="Alipay"> |

或者通过 [GitHub Sponsors](https://github.com/sponsors/songpl-AI) 支持。

## 🤝 贡献

欢迎提交 Issue 或 Pull Request！

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。
