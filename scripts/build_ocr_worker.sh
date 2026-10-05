#!/bin/bash
set -euo pipefail
# Invoked by Xcode for every app configuration, including archive and previews.
task_root="${SRCROOT:?}/.."
# Xcode's script sandbox permits temporary descendants, whereas declared
# directory outputs only grant access to the directory itself during archive.
task_build="${TEMP_DIR:?}/OCRWorker"
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
# lipo and codesign create sibling temporary files, so finish both in TEMP_DIR
# before copying the completed executable to the declared output file.
task_product="$task_build/LibreShotOCRWorker"
xcrun lipo -create "${task_binaries[@]}" -output "$task_product"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == YES ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime \
        --entitlements "$task_root/OCRWorker/Worker.entitlements" "$task_product"
fi
cp "$task_product" "$task_output"
