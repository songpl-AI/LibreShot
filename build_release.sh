#!/bin/bash

# 设置项目路径和名称
PROJECT_ROOT="LibreShot"
PROJECT_NAME="LibreShot"
SCHEME_NAME="LibreShot"
BUILD_DIR="$(pwd)/build"
DMG_NAME="${PROJECT_NAME}.dmg"

# 清理旧构建
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "🚀 开始构建 ${PROJECT_NAME}..."

# 1. 归档 (Archive)
# 使用 CODE_SIGN_IDENTITY="-" 进行临时签名，或者依赖 Xcode 项目中的设置
xcodebuild archive \
  -project "${PROJECT_ROOT}/${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME_NAME}" \
  -configuration Release \
  -archivePath "${BUILD_DIR}/${PROJECT_NAME}.xcarchive" \
  -quiet || { echo "❌ 构建失败"; exit 1; }

echo "✅ 归档完成"

# 2. 导出 .app
# 直接从归档中提取 .app
APP_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive/Products/Applications/${PROJECT_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 未找到 .app 文件: $APP_PATH"
    exit 1
fi

cp -R "$APP_PATH" "$BUILD_DIR/"

echo "✅ 已导出 ${PROJECT_NAME}.app"

# 3. 创建 DMG
echo "📦 正在创建 DMG 安装包..."

# 创建临时文件夹用于生成 DMG
DMG_SRC_DIR="${BUILD_DIR}/dmg_source"
mkdir -p "$DMG_SRC_DIR"
cp -R "${BUILD_DIR}/${PROJECT_NAME}.app" "$DMG_SRC_DIR/"
ln -s /Applications "$DMG_SRC_DIR/Applications"

# 使用 hdiutil 创建 DMG
hdiutil create \
  -volname "${PROJECT_NAME}" \
  -srcfolder "$DMG_SRC_DIR" \
  -ov -format UDZO \
  "${BUILD_DIR}/${DMG_NAME}" \
  -quiet || { echo "❌ DMG 创建失败"; exit 1; }

# 清理临时文件
rm -rf "$DMG_SRC_DIR"

echo "🎉 构建成功！"
echo "📂 安装包位置: ${BUILD_DIR}/${DMG_NAME}"
echo "   (你可以将此文件上传到 GitHub Releases)"
