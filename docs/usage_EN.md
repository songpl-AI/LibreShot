# Usage guide

[README](../README_EN.md) · [中文](usage.md)

## Start a capture

Use the scissors menu for area, full-screen or scrolling capture. Default shortcuts are `⌘⇧X` for area and `⌘⇧A` for full-screen; customize them in Settings. Optional double-Option requires Input Monitoring.

Full-screen captures the display under the pointer and opens annotation editing. Area capture defaults to Select/Move after selecting a region; change the default tool in toolbar settings. Outer handles resize the capture region.

Left-click the menu bar scissors to start area capture by default; right-click opens the full menu. Change the left-click action in General settings. Fine dashed crosshair guides appear while selecting and can be disabled in Settings.

## Annotation and properties

Selecting a tool or existing annotation directly shows a compact property bar; narrow screens wrap controls into rows. Short sliders preview numeric changes live; release to finish one adjustment, which can be undone in one step. Edit the current value for precision: Return commits, Esc discards the draft, and invalid input leaves the property unchanged. Quick colors are red, green and blue; the adjacent palette icon opens the system color panel for custom colors. Each tool remembers its own color, width, font size and effect settings. Reset affects only that tool. `⌘Z` undoes object changes; explicitly chosen preferences for future annotations remain saved.

In Select/Move mode, drag blank space inside the capture region to move the entire region and its annotations. Drag an annotation to adjust that object; crop handles still resize the capture. Drawing tools remain active after drawing for continuous annotation. Click Select/Move, or click the active tool again, before moving the crop from blank space. Small click jitter does not move the crop, and blank double-click completion still works. Movement stays within the screen and resumes when dragging back from its edge. Image and long-image editors keep their document crop fixed.

First-use and reset defaults are: stroke width 3, text size 24, number size 16, rectangle corner radius 8, mosaic grain 16, blur intensity 12 and effect brush width 20. Saved custom choices still take precedence. Older rectangles without a corner setting retain square corners until reset applies radius 8.

- **Rectangle, ellipse, arrow and pen**: Drag on empty space to draw. Set rectangle corner radius with a slider or exact input (0–128); 0 means square corners. The effective radius never exceeds half the shorter side.
- **Select and adjust**: In Select/Move mode, press and drag a rectangle or ellipse (interior or outline) to move it immediately. With another tool active, press an outline showing the hand cursor to move it without a preliminary click; the interior stays a drawing area. Clicking still selects; handles resize and arrow endpoints adjust. Delete/Backspace removes the selection; `⌘Z` undoes. Select/Move or clicking the active tool again returns to selection mode.
- **Text**: Choose Text, click the image and type inline. Return inserts a line break; click empty space to commit. Resize selected text with its bottom-right handle.
- **Numbers**: Click to place incrementing numbers. Set filled/outlined style, size and independent border, fill and digit colors. The quick palette adjusts fill for filled numbers or border for outlined numbers. Open More Color Settings to choose a color target and use the shared palette or a custom color. Outline mode hides fill options; filled numbers can have no border, and digits support automatic coloring. Switching modes retains the fill preference.
- **Edit numbers**: Double-click existing text or numbers to edit, even when double-click completion is enabled. Numbers accept 1–9999; Return commits and Esc cancels the edit. Setting N makes the next number N+1. Resize with the bottom-right handle. Deleting the most recently placed or edited number can roll back the next number; deleting a middle number does not renumber others.
- **Mosaic and blur**: Choose Brush or Rectangle in the property bar, then set brush size, block size or blur strength. Continue brushing after releasing the pointer; use Select/Move to edit existing strokes.

## Finish, copy and save

Double-click a blank area inside the selection, press Return or click ✅ to finish. Auto Save is off for new users, so finishing copies only; upgrades preserve existing choices. Enabling it copies and saves on completion.

- `⌘S` / Save always writes to the configured folder independently of Auto Save.
- `⌘⇧S` / Save As opens a dialog starting in that folder, with a choice of name and location.
- Failed automatic saving reports an error and leaves the image on the clipboard.
- Saving an area capture ends that session; manual saving in the full-screen editor keeps it open.
- Esc cancels a capture, including while entering text. While editing a number, it first cancels the number edit; press again to cancel the capture.

Double-click completion can be disabled in Settings. Double-clicks on annotations, handles, the toolbar or properties do not finish the capture, nor do double-clicks during text editing. Space can be Off (default), Finish, or Save & Copy. While entering text, Space and Return retain their normal input behavior.

## Pin and scrolling capture

Click Pin or use the default `⌘P` during capture editing to pin at the capture position. The wheel or Cmd+wheel zooms and briefly shows the current percentage; Ctrl+wheel adjusts display opacity. Copy and Save retain the original pixel dimensions and image opacity. Outside editing, drag to move and double-click to close; Close is also available in the context menu.

Choose Edit Annotations from the context menu to edit in place. Changes persist immediately. Drag blank space in Select/Move mode to move the pin; drawing tools still draw. The toolbar's left handle moves the pin with any tool. With blank double-click completion enabled, double-clicking blank space during pin editing saves to the configured folder and keeps editing open. Collapse with the right arrow or Esc, then reopen to continue undoing with `⌘Z`. Text input handles Esc first; existing text, numbers and handles do not trigger saving.

Global recall of the most recent capture and history browsing are not included. `⌘P` is an editing shortcut.

Start scrolling capture from the menu bar or capture toolbar. Select a region, then scroll while keeping overlapping content between frames. Return finishes; Esc cancels. The result opens for scrolling, zooming and annotation by default. Disable post-capture editing in Settings for a preview-first copy/save workflow.

## OCR and translation

OCR keeps the screenshot visible and marks the recognized lines: click to select one line, drag across text to select arbitrary characters or phrases, `⌘A` to select all, `⌘C` to copy; with nothing selected, `⌘C` copies all text, and Return also copies. Double-click a line to copy it. Use the Layer/List switch to open the full text window for review or translation. Translation requires macOS 26+. Missing language packs prompt a download; installed languages work offline. Retry after cancelling; approved downloads may continue in the background. Manage packs in System Settings → General → Language & Region → Translation Languages.

Translate in Place puts translations at the original text positions. Edit individual translations, switch original/translated views, copy, save or continue annotating. Shorten or exclude overflowing regions before export. Complex textures, tables and unusual fonts need review; seamless background reconstruction is not guaranteed.

Screenshots, OCR and translation text are processed locally. Initial language-pack downloads and update checks need internet access.

## Settings

Use the menu bar or `⌘,` while LibreShot is active. Configure save folder, Auto Save, launch at login, capture sound, capture corners, shortcuts, double-Option, double-click completion and Space behavior.

Toolbar settings control visibility, order, editor shortcuts, the default tool and left/center/right alignment. Hover a property slider to see its value and adjust it with the wheel. Complete and Cancel always remain visible. Changes apply to the next capture. Hiding the default tool falls back to Select/Move. Restore Defaults resets visibility, order and the default tool.
