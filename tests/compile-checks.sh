#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_output=$1
shift
task_flags=(-parse-as-library)
if [[ "${LIBRESHOT_OPTIMIZE:-0}" == 1 ]]; then task_flags+=(-O); fi
xcrun swiftc "${task_flags[@]}" \
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
  LibreShot/LibreShot/Core/OCR/ImageTranslationRenderer.swift \
  LibreShot/LibreShot/Core/OCR/ImageTranslationWindowController.swift \
  LibreShot/LibreShot/Core/Storage/ToolbarConfiguration.swift \
  LibreShot/LibreShot/Core/Storage/EditorShortcuts.swift \
  LibreShot/LibreShot/Core/Storage/SettingsService.swift \
  LibreShot/LibreShot/Core/Hotkey/HotkeyService.swift \
  LibreShot/LibreShot/Features/Settings/SettingsView.swift \
  LibreShot/LibreShot/Features/Settings/SettingsWindowController.swift \
  LibreShot/LibreShot/Features/Settings/ShortcutRecorder.swift \
  "$@" -o "$task_output"
