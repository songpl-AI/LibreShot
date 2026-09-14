#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-issue4-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
xcrun swiftc -parse-as-library \
  LibreShot/LibreShot/CaptureService.swift \
  LibreShot/LibreShot/CaptureService+Annotation.swift \
  LibreShot/LibreShot/Core/ImageEditorWindowController.swift \
  LibreShot/Editor/Annotation.swift \
  LibreShot/Editor/EditorToolbarView.swift \
  LibreShot/Features/Overlay/OverlayViewModel.swift \
  LibreShot/Features/Overlay/OverlayView.swift \
  LibreShot/LibreShot/Core/InlineTextEditor.swift \
  LibreShot/LibreShot/Core/OverlayWindow.swift \
  LibreShot/LibreShot/Core/OCR/OCRService.swift \
  LibreShot/LibreShot/Core/OCR/TranslationService.swift \
  LibreShot/LibreShot/Core/OCR/OCRResultWindowController.swift \
  LibreShot/LibreShot/Core/Storage/ToolbarConfiguration.swift \
  LibreShot/LibreShot/Core/Storage/SettingsService.swift \
  LibreShot/LibreShot/Core/Hotkey/HotkeyService.swift \
  LibreShot/LibreShot/Features/Settings/SettingsView.swift \
  LibreShot/LibreShot/Features/Settings/ShortcutRecorder.swift \
  tests/Issue4RegressionChecks.swift \
  -o "$task_tmp/checks"
"$task_tmp/checks"
task_clipboard="LibreShot.ClipboardCheck.$(uuidgen)"
"$task_tmp/checks" --clipboard-write "$task_clipboard"
"$task_tmp/checks" --clipboard-read "$task_clipboard"
