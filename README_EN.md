# LibreShot

[中文](README.md) | [English](README_EN.md)

LibreShot is a lightweight, modern screenshot and annotation tool for macOS, built natively with Swift. It is completely free and open source.

## ✨ Features

- **Minimalist Design**: Native macOS style, lightweight and fast, seamlessly integrated into the system.
- **Rich Annotation Tools**:
  - 🖊️ **Pen**: Freehand drawing.
  - ⬜ **Rectangle/Ellipse**: Quickly highlight areas.
  - ↖️ **Arrow**: Point out details precisely.
  - 📝 **Text**: Add text explanations.
  - 💧 **Blur/Mosaic**: Easily hide sensitive information (like faces, accounts).
- **OCR Text Recognition**: Built-in offline OCR engine to extract text from screenshots (supports Chinese & English) with one click. No internet connection required, protecting your privacy.
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
open LibreShot.xcodeproj

# 3. Build and Run using Xcode (Cmd + R)
```
*Requirements: Xcode 14.0+, macOS 13.0+*

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
After taking a screenshot, it will automatically enter edit mode. The top toolbar provides the following functions:
- **Shapes**: Rectangle, Circle, or Arrow.
- **Mosaic/Blur**: Click the drop icon to select areas to blur.
- **Text**: Click the "T" icon to insert text.
- **Color/Stroke**: Adjust color and line width when an annotation object is selected.

### 4. Pin to Screen
Click the **📌 (Pin)** icon on the toolbar to pin the current screenshot as a floating window on top of the screen. You can drag it around and double-click to close it. This is very useful for code comparison or reference.

### 5. OCR
Click the **OCR** icon on the toolbar. The software will automatically recognize text in the screenshot and show the result in a popup window, supporting one-click copy.

### 6. Settings
Click the icon in the menu bar and select "Settings..." to:
- **Set Shortcuts**: Customize global shortcuts for "Area Screenshot" and "Full Screen Screenshot".
- **Save Path**: Customize the default save location for screenshots.
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
