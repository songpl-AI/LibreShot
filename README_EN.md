# LibreShot

[中文](README.md) | [English](README_EN.md)

LibreShot is a lightweight, modern screenshot and annotation tool for macOS, built natively with Swift. It is completely free and open source.

Latest public release: [v1.3.5](https://github.com/songpl-AI/LibreShot/releases/tag/v1.3.5) · [Release notes](docs/releases/1.3.5.md) · [Changelog](CHANGELOG.md)

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
- **Translate in Place**: Put editable translations at the original text positions, switch between original and translated images, then copy, save, or annotate (macOS 26+). Best suited to documents and interfaces with simple backgrounds; complex backgrounds are not reconstructed seamlessly.
- **Long Screenshot**: Capture scrolling content into one long image and, by default, open it in a scrollable, zoomable annotation window. You can choose a preview-first workflow in Settings.
- **Auto Save**: Finishing an area capture with ✅ copies the image and also saves it to your chosen folder when Auto Save is enabled. A manual "Save As" option remains available.
- **Custom Toolbar**: Show, hide, and reorder tools in Settings. Enabled tools remain directly visible and wrap on narrow windows, without a More menu.
- **Pin to Screen**: Support "pinning" screenshots to the top of the screen for easy reference or cross-app collaboration.
- **Shortcuts**: Customize global capture and editor-tool shortcuts, optionally capture by double-tapping Option, and assign Finish or Save & Copy to Space.
- **On-Device Processing**: Screenshots, OCR, and translation text are processed locally. Initial language downloads and update checks require internet access.
- **Completely Free**: Open source and free, breaking down payment barriers.

## 📦 Installation

### Method 1: GitHub Releases (Recommended)

> 💻 **System Requirements**: macOS 13.0 (Ventura) or later.

1. Go to the [Releases](https://github.com/songpl-AI/LibreShot/releases) page to download the latest `.dmg` installer.
2. Double-click the `.dmg` file and drag `LibreShot.app` into the `Applications` folder.

To upgrade, quit LibreShot and replace the old app in Applications. Your toolbar and save preferences are retained. The installer supports Apple Silicon and Intel; translation requires macOS 26 or later.

GitHub packages use ad-hoc signatures and are **not notarized**. macOS may block it by default. Download only from this repository's Release page, verify the `SHA256SUMS` attachment, and follow [Apple's official app-opening instructions](https://support.apple.com/102445) in System Settings → Privacy & Security. Do not disable Gatekeeper globally. If macOS reports a damaged file, redownload and verify the checksum first. This is not a friction-free Developer ID-signed, notarized installer.

Before the first capture, allow LibreShot under Screen Recording (or Screen & System Audio Recording) in System Settings → Privacy & Security. Double-Option also requires Input Monitoring. An upgrade between temporarily signed builds may require you to grant both permissions again and quit/reopen LibreShot.

If permission is enabled but the new app still reports it missing, quit LibreShot, remove its old entry in the relevant permission panel, and add `/Applications/LibreShot.app` using “+”. Enable it and reopen the app. Check Screen Recording and Input Monitoring separately, capture and save an image, then restart the same installed app and repeat. Maintainers must follow the [installation and permission acceptance procedure (Chinese)](docs/operations/install-and-permissions.md) for every new package.

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

GitHub distribution defaults to ad-hoc signing: run `bash build_release.sh`, or specify `--ad-hoc` explicitly. Users may need to grant Screen Recording and Input Monitoring again after each update, and this package cannot be notarized. If you later configure a Developer ID Application certificate, use `bash build_release.sh --developer-id`. The script checks the signing mode, preserves existing outputs, and does not notarize or upload. See [regression checks](tests/README.md) and the [1.3.5 release notes](docs/releases/1.3.5.md).

## 🚀 Usage Guide

Capture editing defaults to Select/Move. You can choose another default annotation tool in toolbar settings. Version 1.3.4 also fixes irregular freehand selection bounds and reduces accidental marks or movement.

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


**New in 1.3.3:** Mosaic annotations now have eight resize handles and directional hover cursors, without the extra selection outline. Resizing supports undo. See the [release notes](docs/releases/1.3.3.md).

**New in 1.3.2:** Clicks and small pointer jitter no longer create invalid shapes. Completed shapes are immediately selected, and selecting an existing annotation keeps its tool active for drawing in empty space. Drag selected annotations to move them, or drag arrow endpoints to change direction. Delete/Backspace removes the selected annotation; Cmd-Z undoes deletion and adjustments. Text input keeps its normal delete behavior. Rounded selection previews match the output. Editor shortcuts are now beside the toolbar ordering rows; the Space action remains on the Shortcuts tab. See the [validation record](docs/qa/issue-9-20261002.md).

**New in 1.2.0**: Click an existing annotation to select it while any annotation tool is active. For rectangles and ellipses, click the outline. Drag a selected annotation to move it; selected rectangles and ellipses also have eight blue resize handles and can be moved from their empty interiors. White outer handles resize the capture region. A direct drag still draws with the active tool; double-clicking text still edits it.

**New in 1.3.5:** Configure the default capture tool, double-click to edit numbers, and resize numbered annotations with size/color inheritance. See the [release notes](docs/releases/1.3.5.md).

After selecting a capture region, edit mode opens with resize handles at all four corners and edge midpoints. Press `Esc` once to cancel the capture, including while entering text. While editing a number, Esc first cancels the number edit. Click Select/Move or click the active tool again to return to selection mode. The floating toolbar provides the following functions:
- **Shapes**: Rectangle, Circle, or Arrow.
- **Numbered Annotation**: Click the number icon to place a circled auto-incrementing number. Double-click a number to edit it (1–9999); Enter commits and Esc cancels the edit. Setting N makes the next number N+1. Drag the bottom-right handle to resize; subsequent numbers inherit size and color. Deleting the most recently placed or edited number rolls back the next number; middle deletions leave other numbers unchanged. Cmd-Z undoes these edits.
- **Mosaic/Blur**: The development version of 1.3.6 supports Brush and Rectangle modes for both tools, selected in Effect Parameters, with continuously refreshed previews during dragging. Adjust mosaic block size, brush width and blur strength; selected effect parameters can be edited and undone. The latest live-preview changes are packaged as 1.3.6 build 26 and have passed local installation, permission renewal, and capture/save checks before and after restart; user trial feedback is pending. The public release remains 1.3.5.
- **Text**: Click the "T" icon and click on the image to type inline (WYSIWYG); press Enter for a new line, click elsewhere to commit.
- **Color & Font Size**: Click the four-color palette (red, yellow, blue, green) to open color presets, the system color picker, and font sizes. The thin bar below the palette shows the current color; drag the bottom-right handle of selected text to scale it proportionally.

### 4. Pin to Screen
Click the **📌 (Pin)** icon on the toolbar to pin the current screenshot as a floating window on top of the screen. You can drag it around and double-click to close it. This is very useful for code comparison or reference.

### 5. Long Screenshot
Select Long Screenshot from the menu bar, or use its button in the capture toolbar. Select the content region, then scroll with overlapping content between frames. Press Return to finish or Esc to cancel. By default the result opens for scrolling, zooming, and annotation. Turn off post-capture editing in Settings for a preview-first Copy/Save workflow. Save follows your Auto Save preference; Save As always opens a file dialog.

### 6. OCR & Translation
Click the **OCR** icon on the toolbar. The software will automatically recognize text in the screenshot and show the result in a popup window, supporting one-click copy; you can also translate the result offline by choosing a target language (macOS 26+). If languages are missing, macOS prompts you to download the free language packs. The initial download requires internet access; installed languages translate directly. You can retry after cancelling. Manage packs in System Settings → General → Language & Region → Translation Languages. Downloads you have approved may continue in the background under macOS.

**Translate in Place** replaces recognized text at its position in the image. You can edit individual translations, switch between original and translated views, then copy, save, or continue annotating. Shorten or exclude an overflowing region before export. Adjacent paragraph lines use a consistent type size, but complex textures, tables, and unusual fonts may need manual review.

### 7. Settings
Click the scissors icon in the menu bar and select "Settings...", or press `Cmd + ,` while LibreShot is active, to:
- **Set Shortcuts**: Customize global shortcuts for "Area Screenshot" and "Full Screen Screenshot".
- **Editor Shortcuts**: Assign keys to annotation tools. Defaults include Cmd-S to save, Shift-Cmd-S for Save As, Return to finish, and Cmd-Z to undo. Ordinary characters, Space, and Return still work while entering text; Esc cancels the capture, except while editing a number, when it cancels that edit first.
- **Double Option**: Optionally start an area capture with two Option taps. Requires Input Monitoring permission; modifier combinations, long presses, and intervening mouse actions do not trigger it.
- **Space Action**: Choose Off (default), Finish, or Save & Copy. Finish follows Auto Save; Save & Copy always writes to the configured folder and preserves the clipboard image if saving fails.
- **Save Path**: Customize the default save location for screenshots.
- **Auto Save**: When enabled, ✅ copies and saves an area capture. When disabled, it only copies. If saving fails, an alert appears and the screenshot remains on the clipboard.
- **Toolbar**: Show or hide buttons and reorder them by dragging rows or clicking the up/down arrows. Hidden tools retain their positions; Complete and Cancel can move but always remain visible. Changes are saved automatically and apply to the next capture. Choose a default annotation tool for new captures; the factory default is Select/Move. Restore Defaults restores visibility, order, and the default tool. Hiding the default tool returns to selection mode; click the active tool again to return to selection mode if its button is hidden. `Esc` cancels the capture; while editing a number, it first cancels that edit.
- **Launch Settings**: Set whether to launch at login.

## ❤️ Support

LibreShot is a free and open-source project. If you find it helpful, please consider buying the author a coffee to encourage maintenance and updates!

| WeChat|
| :---: |
| <img src="docs/wechat.JPG" width="200" alt="WeChat"> 

Or support via [GitHub Sponsors](https://github.com/sponsors/songpl-AI).

## Follow-ups and Validation

Automatic annotation selection and rectangle/ellipse resizing are available in 1.2.0. See the [release notes](docs/releases/1.2.0.md) and [annotation checks](docs/qa/1.2.0.md). Hiding buttons simplifies the toolbar; it does not uninstall features or imply substantial memory savings.

v1.3.2 passed package, installation, permission renewal, capture/save, OCR, and same-signature restart checks on Apple Silicon / macOS 26. A real Finder replay of 133 frames produced pixel-identical output. Intel, macOS 13/14, multiple displays, and more scrolling scenarios still need feedback. The approximately 10 MiB memory target was withdrawn on 2026-10-05 and [Issue #5](https://github.com/songpl-AI/LibreShot/issues/5) was closed as not planned; this does not claim the target was achieved. See the [v1.3.2 validation](docs/qa/1.3.2-20-package-20261005.md) and [capture checks](docs/qa/1.1.0.md).

## 🤝 Contributing

Issues and Pull Requests are welcome!

## 📄 License

This project is open source under the [MIT License](LICENSE).
