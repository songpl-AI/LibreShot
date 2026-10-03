#!/bin/bash
set -euo pipefail
# Invoked by Xcode for every app configuration, including archive and previews.
task_root="${SRCROOT:?}/.."
task_build="${DERIVED_FILE_DIR:?}/OCRWorker"
task_output="${TARGET_BUILD_DIR:?}/${EXECUTABLE_FOLDER_PATH:?}/LibreShotOCRWorker"
mkdir -p "$task_build" "$(dirname "$task_output")"
task_binaries=()
for task_arch in ${ARCHS:?}; do
    task_binary="$task_build/LibreShotOCRWorker-$task_arch"
    xcrun swiftc -parse-as-library -O -swift-version 5 \
        -sdk "$SDKROOT" -target "$task_arch-apple-macosx${MACOSX_DEPLOYMENT_TARGET}" \
        -module-cache-path "$task_build/ModuleCache" \
        "$task_root/LibreShot/LibreShot/Core/OCR/OCREngine.swift" \
        "$task_root/LibreShot/LibreShot/Core/OCR/OCRWire.swift" \
        "$task_root/OCRWorker/Worker.swift" -o "$task_binary"
    task_binaries+=("$task_binary")
done
xcrun lipo -create "${task_binaries[@]}" -output "$task_output"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == YES ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime \
        --entitlements "$task_root/OCRWorker/Worker.entitlements" "$task_output"
fi
