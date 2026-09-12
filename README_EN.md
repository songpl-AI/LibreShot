# LibreShot

[中文](README.md) | [English](README_EN.md)

LibreShot is a lightweight, modern screenshot and annotation tool for macOS, built natively with Swift. It is completely free and open source.

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
- **Privacy First**: Runs completely offline, no data is uploaded.
- **Completely Free**: Open source and free, breaking down payment barriers.

## 📦 Installation

### Method 1: GitHub Releases (Recommended)

> 💻 **System Requirements**: macOS 13.0 (Ventura) or later.

1. Go to the [Releases](https://github.com/songpl-AI/LibreShot/releases) page to download the latest `.dmg` installer.
2. Double-click the `.dmg` file and drag `LibreShot.app` into the `Applications` folder.

> ⚠️ **Note: If you encounter "Cannot verify developer"**
> 
> Please follow these steps (only needed once):
> 1. Double-click to open `LibreShot.dmg`.
> 2. Drag `LibreShot.app` into the `Applications` folder.
> 3. Click the `LibreShot.app` icon. In "Privacy & Security" settings, click **"Open Anyway"**.
> 4. Ignore security prompts. This software is strictly offline and will not connect to the internet.

If it still prompts "File is damaged", please run the following command in the terminal to fix it:
```bash
xattr -cr /Applications/LibreShot.app
```

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

Run `bash build_release.sh` to create a locally signed app, DMG, and SHA256 checksum in a new `dist/` subdirectory. The script preserves existing outputs and does not notarize or upload. See [regression checks](tests/README.md) and the [1.1.0 release notes](docs/releases/1.1.0.md).

## 🚀 Usage Guide

### 1. Shortcuts (Recommended)
- **Area Screenshot**: Default `Cmd + Shift + X`
- **Full Screen Screenshot**: Default `Cmd + Shift + A`

You can customize these shortcuts in **Settings**. This is the most efficient way to use the tool.

### 2. Menu Bar
Click the "Scissors" icon in the menu bar to select functions:
- **Area Screenshot**
- **Full Screen Screenshot**

*(Note: The global shortcut currently bound will be displayed next to the menu item for easy reference)*

### 3. Annotation & Editing
After selecting a capture region, edit mode opens with resize handles at all four corners and edge midpoints. Press `Esc` once to cancel the capture, including while entering text. Click Select/Move or click the active tool again to return to selection mode. The floating toolbar provides the following functions:
- **Shapes**: Rectangle, Circle, or Arrow.
- **Numbered Annotation**: Click the number icon to place a circled auto-incrementing number.
- **Mosaic/Blur**: Click the drop icon to select areas to blur.
- **Text**: Click the "T" icon and click on the image to type inline (WYSIWYG); press Enter for a new line, click elsewhere to commit.
- **Color & Font Size**: Click the four-color palette (red, yellow, blue, green) to open color presets, the system color picker, and font sizes. The thin bar below the palette shows the current color; drag the bottom-right handle of selected text to scale it proportionally.

### 4. Pin to Screen
Click the **📌 (Pin)** icon on the toolbar to pin the current screenshot as a floating window on top of the screen. You can drag it around and double-click to close it. This is very useful for code comparison or reference.

### 5. OCR & Translation
Click the **OCR** icon on the toolbar. The software will automatically recognize text in the screenshot and show the result in a popup window, supporting one-click copy; you can also translate the result offline by choosing a target language (macOS 26+). If languages are missing, macOS prompts you to download the free language packs. The initial download requires internet access; installed languages translate directly. You can retry after cancelling.

### 6. Settings
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

## 🤝 Contributing

Issues and Pull Requests are welcome!

## 📄 License

This project is open source under the [MIT License](LICENSE).
