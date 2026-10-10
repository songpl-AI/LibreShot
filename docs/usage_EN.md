# Usage guide

[README](../README_EN.md) · [中文](usage.md)

## Start a capture

Use the scissors menu for area, full-screen or scrolling capture. Default shortcuts are `⌘⇧X` for area and `⌘⇧A` for full-screen; customize them in Settings. Optional double-Option requires Input Monitoring.

Full-screen captures the display under the pointer and opens annotation editing. Area capture defaults to Select/Move after selecting a region; change the default tool in toolbar settings. Outer handles resize the capture region.

## Annotation and properties

Selecting a tool or existing annotation shows its properties automatically. Each tool remembers its own color, width, font size and effect settings. Reset affects only that tool. `⌘Z` undoes object changes; explicitly chosen preferences for future annotations remain saved.

- **Rectangle, ellipse, arrow and pen**: Drag on empty space to draw. Rectangle corner options are 0, 4, 8, 16, 24 and 32; 0 means square corners. The effective radius never exceeds half the shorter side.
- **Select and adjust**: Click an annotation to select it; click rectangle/ellipse outlines. Drag to move, use handles to resize, or adjust arrow endpoints. Delete/Backspace removes the selection; `⌘Z` undoes. Select/Move or clicking the active tool again returns to selection mode.
- **Text**: Choose Text, click the image and type inline. Return inserts a line break; click empty space to commit. Resize selected text with its bottom-right handle.
- **Numbers**: Click to place incrementing numbers. Set filled/outlined style, size and independent border, fill and digit colors. Choose a color target, then use the shared palette. Outline mode hides fill options; filled numbers can have no border, and digits support automatic coloring. Switching modes retains the fill preference.
- **Edit numbers**: Disable Double-click to finish capture to double-click and edit text or numbers. Numbers accept 1–9999; Return commits and Esc cancels the edit. Setting N makes the next number N+1. Resize with the bottom-right handle. Deleting the most recently placed or edited number can roll back the next number; deleting a middle number does not renumber others.
- **Mosaic and blur**: Choose Brush or Rectangle in the property bar, then set brush size, block size or blur strength. Continue brushing after releasing the pointer; use Select/Move to edit existing strokes.

## Finish, copy and save

Double-click the selected image, press Return or click ✅ to finish. Auto Save is off for new users, so finishing copies only; upgrades preserve existing choices. Enabling it copies and saves on completion.

- `⌘S` / Save always writes to the configured folder independently of Auto Save.
- `⌘⇧S` / Save As opens a dialog starting in that folder, with a choice of name and location.
- Failed automatic saving reports an error and leaves the image on the clipboard.
- Saving an area capture ends that session; manual saving in the full-screen editor keeps it open.
- Esc cancels a capture, including while entering text. While editing a number, it first cancels the number edit; press again to cancel the capture.

Disable double-click completion to restore double-click editing. Space can be Off (default), Finish, or Save & Copy. While entering text, Space and Return retain their normal input behavior.

## Pin and scrolling capture

Pin creates an always-on-top image. Drag it to move; double-click to close.

Start scrolling capture from the menu bar or capture toolbar. Select a region, then scroll while keeping overlapping content between frames. Return finishes; Esc cancels. The result opens for scrolling, zooming and annotation by default. Disable post-capture editing in Settings for a preview-first copy/save workflow.

## OCR and translation

OCR extracts text into a result window for review, copying or translation. Translation requires macOS 26+. Missing language packs prompt a download; installed languages work offline. Retry after cancelling; approved downloads may continue in the background. Manage packs in System Settings → General → Language & Region → Translation Languages.

Translate in Place puts translations at the original text positions. Edit individual translations, switch original/translated views, copy, save or continue annotating. Shorten or exclude overflowing regions before export. Complex textures, tables and unusual fonts need review; seamless background reconstruction is not guaranteed.

Screenshots, OCR and translation text are processed locally. Initial language-pack downloads and update checks need internet access.

## Settings

Use the menu bar or `⌘,` while LibreShot is active. Configure save folder, Auto Save, launch at login, capture corners, shortcuts, double-Option, double-click completion and Space behavior.

Toolbar settings control visibility, order, editor shortcuts and the default tool. Complete and Cancel always remain visible. Changes apply to the next capture. Hiding the default tool falls back to Select/Move. Restore Defaults resets visibility, order and the default tool.
