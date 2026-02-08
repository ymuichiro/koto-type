#!/bin/bash
set -e

echo "Creating STTApp.app bundle..."
echo ""
echo "注意: 事前に 'make build-server' を実行してwhisper_serverバイナリを作成してください"
echo "コマンド: cd .. && make build-server"
echo ""

# 設定
APP_NAME="STTApp"
BUILD_DIR=".build/debug"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 既存のバンドルを削除
if [ -d "${BUNDLE_NAME}" ]; then
    echo "Removing existing bundle..."
    rm -rf "${BUNDLE_NAME}"
fi

# ディレクトリ構造を作成
echo "Creating bundle structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 実行ファイルをコピー
echo "Copying executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# whisper_serverバイナリをコピー
if [ -f "../dist/whisper_server" ]; then
    echo "Copying whisper_server binary..."
    cp "../dist/whisper_server" "${RESOURCES_DIR}/"
    chmod +x "${RESOURCES_DIR}/whisper_server"
else
    echo "Warning: whisper_server binary not found in ../dist/"
    echo "Please run: cd .. && pyinstaller --onefile --name whisper_server python/whisper_server.py"
fi

# Info.plistを作成
echo "Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>STTApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.stt.app</string>
	<key>CFBundleName</key>
	<string>STTApp</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>音声録音のためにマイクを使用します</string>
	<key>NSSupportsAutomaticTermination</key>
	<true/>
	<key>NSSupportsSuddenTermination</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>他のアプリと連携するためにApple Eventsを使用します</string>
</dict>
</plist>
EOF

# アドホック署名
echo "Applying ad-hoc signature..."
codesign --force --deep --sign - "${BUNDLE_NAME}" 2>/dev/null || true

echo "✅ ${BUNDLE_NAME} created successfully!"
echo "Bundle location: $(pwd)/${BUNDLE_NAME}"
echo ""
echo "To launch: open ${BUNDLE_NAME}"
