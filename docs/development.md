# 开发指南

[返回 README](../README.md) · [English](development_EN.md)

## 从源码运行

当前源码使用 macOS 26 SDK，需要 Xcode 26 或更新版本；部署目标为 macOS 13。

```bash
git clone https://github.com/songpl-AI/LibreShot.git
cd LibreShot
open LibreShot/LibreShot.xcodeproj
```

在 Xcode 中选择 LibreShot，按 `⌘R` 编译运行。开发副本的权限与正式安装包分别验收。

## 构建发行包

```bash
bash build_release.sh --ad-hoc
```

默认使用 ad-hoc 签名，核对主应用、OCR helper、架构与沙盒，不自动公证或上传。不同构建可能需要重新授予录屏和输入监控权限。

配置 Developer ID Application 证书后，可使用 `bash build_release.sh --developer-id`；仍需自行安排公证。维护者本机换包使用 [固定脚本](operations/local-upgrade-script.md)，按 [安装验收规范](operations/install-and-permissions.md) 完成同包重启前后的实际截图与保存。

## 检查与贡献

检查入口与覆盖范围见 [tests/README.md](../tests/README.md)，例如：

```bash
bash tests/run-tool-properties-checks.sh
bash tests/run-toolbar-checks.sh
bash tests/run-issue25-checks.sh
```

详细记录保留在 `docs/qa/`，历史更新见 [CHANGELOG](../CHANGELOG.md)。发布及 Issue 回复遵循 [发布流程](operations/release-and-issue-response.md)。

提交 Issue 或 Pull Request 时说明问题、修改范围和验证结果。项目采用 [MIT License](../LICENSE)。
