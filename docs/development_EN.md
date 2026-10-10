# Development guide

[README](../README_EN.md) · [中文](development.md)

## Run from source

The current source uses the macOS 26 SDK and requires Xcode 26 or later. The deployment target is macOS 13.

```bash
git clone https://github.com/songpl-AI/LibreShot.git
cd LibreShot
open LibreShot/LibreShot.xcodeproj
```

Choose LibreShot in Xcode and press `⌘R`. Development copies and the installed distribution need separate permission acceptance.

## Build a distribution

```bash
bash build_release.sh --ad-hoc
```

Ad-hoc is the default signing mode. The script checks the main app, OCR helper, architectures and sandbox; it does not notarize or upload. A new build may require Screen Recording and Input Monitoring again.

With a configured Developer ID Application certificate, use `bash build_release.sh --developer-id`; notarization remains a separate step. For local upgrades, maintainers use the [fixed script](operations/local-upgrade-script.md) and follow [installation acceptance](operations/install-and-permissions.md), including real capture and saving before and after restarting the same package. These procedures are documented in Chinese.

## Checks and contributions

See [tests/README.md](../tests/README.md) for test entry points and coverage, including:

```bash
bash tests/run-tool-properties-checks.sh
bash tests/run-toolbar-checks.sh
bash tests/run-issue25-checks.sh
```

Detailed evidence lives in `docs/qa/`; historical changes are in the [changelog](../CHANGELOG.md). Publishing and Issue replies follow the [release workflow](operations/release-and-issue-response.md).

Describe the problem, scope and validation in Issues or Pull Requests. The project uses the [MIT License](../LICENSE).
