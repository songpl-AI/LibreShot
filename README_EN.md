# LibreShot

[中文](README.md) | [English](README_EN.md) · [MIT License](LICENSE)

A free, open-source native screenshot and annotation tool for macOS.

[Download v1.3.14](https://github.com/songpl-AI/LibreShot/releases/tag/v1.3.14) · [Release notes](docs/releases/1.3.14.md) · [Changelog](CHANGELOG.md)

## Features

- **Area, full-screen and scrolling capture**: Capture the screen under the pointer and annotate it; scroll, zoom and edit long captures.
- **Annotation and tool properties**: Pen, rectangle, ellipse, arrow, text, numbers, mosaic and blur. Contextual properties appear automatically with independent preferences, reset and undo.
- **Rounded rectangles and number colors**: Rounded corners, filled/outlined numbers, and independent border, fill and digit colors.
- **OCR and translation**: On-device text recognition, text translation and translation in place. Translation requires macOS 26+; initial language-pack downloads require internet access.
- **Copy, save and pin**: New users finish by copying only, with optional Auto Save, manual Save, Save As and floating pinned images.
- **Custom controls**: Configure shortcuts, toolbar order and the default tool; optionally double-tap Option to start a capture.

## Installation

Supports **macOS 13+, Apple Silicon and Intel**. Translation requires macOS 26+.

1. Download the DMG from [GitHub Releases](https://github.com/songpl-AI/LibreShot/releases).
2. Drag `LibreShot.app` into Applications. Quit the old app before upgrading.
3. Allow Screen Recording for captures; double-Option also requires Input Monitoring.

Packages use ad-hoc signing and are not notarized, so macOS may block opening them. See the [installation guide](docs/installation_EN.md) for checksums, opening the app and renewing upgrade permissions.

## Quick start

1. Choose area, full-screen or scrolling capture from the menu bar, or use a shortcut.
2. Select a region and annotate it. Tool properties appear automatically; rounded corners are in Rectangle Properties.
3. Double-click the selected image, press Return or click ✅ to finish. New users copy only by default. Use `⌘S` to save, `⌘⇧S` for Save As, or `Esc` to cancel.

| Action | Default shortcut |
| --- | --- |
| Area capture | `⌘⇧X` |
| Full-screen capture | `⌘⇧A` |

Customize shortcuts in Settings. Upgrades retain existing preferences. See the [usage guide](docs/usage_EN.md) for details.

## Documentation and feedback

- [Usage guide](docs/usage_EN.md): Annotation, tool properties, saving, scrolling capture and translation.
- [Installation guide](docs/installation_EN.md): Installation, permissions and upgrades.
- [Development guide](docs/development_EN.md): Building, packaging and tests.
- [Issues](https://github.com/songpl-AI/LibreShot/issues): Report bugs or suggest improvements. Pull Requests are welcome.

## Support

Support maintenance through [GitHub Sponsors](https://github.com/sponsors/songpl-AI), or follow the WeChat account.

<img src="docs/wechat.JPG" width="200" alt="WeChat account QR code">

## License

Licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Allen
