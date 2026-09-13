# LibreShot

[中文](README.md) | [English](README_EN.md)

LibreShot is a lightweight, modern screenshot and annotation tool for macOS, built natively with Swift. It is completely free and open source.

Latest public release: [v1.2.0](https://github.com/songpl-AI/LibreShot/releases/tag/v1.2.0) · [Changelog](CHANGELOG.md)

## ✨ Features

- **Minimalist Design**: Native macOS style, lightweight and fast, seamlessly integrated into the system.
- **Rich Annotation Tools**:
  - 🖊️ **Pen**: Freehand drawing.
  - ⬜ **Rectangle/Ellipse**: Quickly highlight areas.
  - ↖️ **Arrow**: Point out details precisely.
  - 📝 **Text**: Inline WYSIWYG editing with multiline, font size and color.
  - 🔢 **Numbered Annotation**: Circled auto-incrementing numbers to highlight points of interest.
  - 💧 **Blur/Mosaic**: Easily hide sensitive information (like faces, accounts).
- **OCR Text Recognition & Translation**: Built-in offline OCR engine to extract text from screenshots (supports Chinese & English), plus offline translation after language packs are installed (macOS 26+; the initial download requires internet access).
- **Long Screenshot**: Capture scrolling content into one long image, with a preview before copy or save.
- **Auto Save**: Finishing an area capture with ✅ copies the image and also saves it to your chosen folder when Auto Save is enabled. A manual "Save As" option remains available.
- **Custom Toolbar**: Choose which tools appear in Settings and reorder them by dragging rows or using the up/down arrows, with a one-click restore to defaults.
- **Pin to Screen**: Support "pinning" screenshots to the top of the screen for easy reference or cross-app collaboration.
- **Global Shortcuts**: Customizable global shortcuts to trigger screenshots instantly.
- **On-Device Processing**: Screenshots, OCR, and translation text are processed locally. Initial language downloads and update checks require internet access.
- **Completely Free**: Open source and free, breaking down payment barriers.

## 📦 Installation

### Method 1: GitHub Releases (Recommended)

> 💻 **System Requirements**: macOS 13.0 (Ventura) or later.

1. Go to the [Releases](https://github.com/songpl-AI/LibreShot/releases) page to download the latest `.dmg` installer.
2. Double-click the `.dmg` file and drag `LibreShot.app` into the `Applications` folder.

To upgrade, quit LibreShot and replace the old app in Applications. Your toolbar and save preferences are retained. The installer supports Apple Silicon and Intel; translation requires macOS 26 or later.

The current package uses a development signature and has not been notarized by Apple. If macOS cannot verify the developer, confirm that you downloaded it from this repository’s Release page and follow [Apple’s app-opening instructions](https://support.apple.com/102445) in System Settings → Privacy & Security. For a damaged-file warning, download again and check the included `SHA256SUMS`.

Before the first capture, allow LibreShot under Screen Recording (or Screen & System Audio Recording) in System Settings → Privacy & Security.

### Method 2: Build from Source

If you are a developer, you can compile the source code yourself:

```bash
# 1. Clone the repository
git clone https://github.com/songpl-AI/LibreShot.git

# 2. Open the project
cd LibreShot
open LibreShot/LibreShot.xcodeproj

# 3. Build and Run using Xcode (Cmd + R)
```
*The current source uses the macOS 26 SDK: use Xcode 26 or later. The app deployment target is macOS 13.0.*

Run `bash build_release.sh` to create a locally signed app, DMG, and SHA256 checksum in a new `dist/` subdirectory. The script preserves existing outputs and does not notarize or upload. See [regression checks](tests/README.md) and the [1.2.0 release notes](docs/releases/1.2.0.md).

## 🚀 Usage Guide

### 1. Shortcuts (Recommended)
- **Area Screenshot**: Default `Cmd + Shift + X`
- **Full Screen Screenshot**: Default `Cmd + Shift + A`

You can customize these shortcuts in **Settings**. This is the most efficient way to use the tool.

### 2. Menu Bar
Click the "Scissors" icon in the menu bar to select functions:
- **Area Screenshot**
- **Full Screen Screenshot**
- **Long Screenshot**

*(Note: The global shortcut currently bound will be displayed next to the menu item for easy reference)*

### 3. Annotation & Editing

**New in 1.2.0**: Click an existing annotation to select it while any annotation tool is active. For rectangles and ellipses, click the outline. Drag a selected annotation to move it; selected rectangles and ellipses also have eight blue resize handles and can be moved from their empty interiors. White outer handles resize the capture region. A direct drag still draws with the active tool; double-clicking text still edits it.

After selecting a capture region, edit mode opens with resize handles at all four corners and edge midpoints. Press `Esc` once to cancel the capture, including while entering text. Click Select/Move or click the active tool again to return to selection mode. The floating toolbar provides the following functions:
- **Shapes**: Rectangle, Circle, or Arrow.
- **Numbered Annotation**: Click the number icon to place a circled auto-incrementing number.
- **Mosaic/Blur**: Choose the corresponding tool and select an area. Hover over a toolbar button to see its name.
- **Text**: Click the "T" icon and click on the image to type inline (WYSIWYG); press Enter for a new line, click elsewhere to commit.
- **Color & Font Size**: Click the four-color palette (red, yellow, blue, green) to open color presets, the system color picker, and font sizes. The thin bar below the palette shows the current color; drag the bottom-right handle of selected text to scale it proportionally.

### 4. Pin to Screen
Click the **📌 (Pin)** icon on the toolbar to pin the current screenshot as a floating window on top of the screen. You can drag it around and double-click to close it. This is very useful for code comparison or reference.

### 5. Long Screenshot
Select Long Screenshot from the menu bar, or use its button in the capture toolbar. Select the content region, then scroll with overlapping content between frames. Press Return to finish or Esc to cancel. The preview offers Copy, Save, and Save As. Save follows your Auto Save preference; Save As always opens a file dialog.

### 6. OCR & Translation
Click the **OCR** icon on the toolbar. The software will automatically recognize text in the screenshot and show the result in a popup window, supporting one-click copy; you can also translate the result offline by choosing a target language (macOS 26+). If languages are missing, macOS prompts you to download the free language packs. The initial download requires internet access; installed languages translate directly. You can retry after cancelling. Manage packs in System Settings → General → Language & Region → Translation Languages. Downloads you have approved may continue in the background under macOS.

### 7. Settings
Click the scissors icon in the menu bar and select "Settings...", or press `Cmd + ,` while LibreShot is active, to:
- **Set Shortcuts**: Customize global shortcuts for "Area Screenshot" and "Full Screen Screenshot".
- **Save Path**: Customize the default save location for screenshots.
- **Auto Save**: When enabled, ✅ copies and saves an area capture. When disabled, it only copies. If saving fails, an alert appears and the screenshot remains on the clipboard.
- **Toolbar**: Show or hide buttons and reorder them by dragging rows or clicking the up/down arrows. Hidden tools retain their positions; Complete and Cancel can move but always remain visible. Changes are saved automatically and apply to the next capture. Restore Defaults restores both visibility and order. Hiding Rectangle starts in selection mode; click the active tool again to return to selection mode if its button is hidden. `Esc` always cancels the capture.
- **Launch Settings**: Set whether to launch at login.

## ❤️ Support

LibreShot is a free and open-source project. If you find it helpful, please consider buying the author a coffee to encourage maintenance and updates!

| WeChat|
| :---: |
| <img src="docs/wechat.JPG" width="200" alt="WeChat"> 

Or support via [GitHub Sponsors](https://github.com/sponsors/songpl-AI).

## Follow-ups and Validation

Automatic annotation selection and rectangle/ellipse resizing are available in 1.2.0. See the [release notes](docs/releases/1.2.0.md) and [annotation checks](docs/qa/1.2.0.md). Hiding buttons simplifies the toolbar; it does not uninstall features or imply substantial memory savings.

Validated on Apple Silicon with macOS 26.5.2. Other macOS versions and Intel hardware still need feedback. See the [capture checks](docs/qa/1.1.0.md) and [translation checks](docs/qa/1.1.1.md).

## 🤝 Contributing

Issues and Pull Requests are welcome!

## 📄 License

This project is open source under the [MIT License](LICENSE).
