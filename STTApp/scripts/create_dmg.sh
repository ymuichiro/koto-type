#!/bin/bash
set -e

APP_NAME="STTApp"
APP_BUNDLE="${APP_NAME}.app"
APP_VERSION="$(./scripts/version.sh)"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
VOL_NAME="STTApp"

echo "Creating DMG for ${APP_BUNDLE}..."

# アプリが存在するか確認
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "❌ Error: ${APP_BUNDLE} not found"
    echo "Please run ./create_app.sh first"
    exit 1
fi

# 一時ディレクトリを作成
TMP_DIR="dmg_temp"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

# アプリをコピー
echo "Copying app bundle..."
cp -R "${APP_BUNDLE}" "${TMP_DIR}/"

# アプリケーションフォルダのシンボリックリンクを作成
echo "Creating Applications link..."
ln -s /Applications "${TMP_DIR}/Applications"

# DMGを作成
echo "Creating DMG..."
hdiutil create -volname "${VOL_NAME}" \
  -srcfolder "${TMP_DIR}" \
  -ov -format UDZO \
  "${DMG_NAME}"

# 一時ディレクトリを削除
rm -rf "${TMP_DIR}"

# DMGにアドホック署名
echo "Applying ad-hoc signature..."
codesign --force --sign - "${DMG_NAME}" 2>/dev/null || true

# DMGサイズを確認
SIZE=$(du -h "${DMG_NAME}" | cut -f1)
echo ""
echo "✅ DMG created successfully!"
echo "File: ${DMG_NAME}"
echo "Size: ${SIZE}"
echo ""
echo "To test: open ${DMG_NAME}"
echo ""
echo "⚠️  Note: This DMG uses ad-hoc signature."
echo "Users will see Gatekeeper warning on first launch."
echo "They can bypass it by right-clicking and selecting 'Open'."
