#!/bin/bash
set -e

validate_app_bundle_layout() {
    local bundle_path="$1"
    local invalid_entries

    if [ ! -d "${bundle_path}/Contents" ]; then
        echo "❌ Error: ${bundle_path} is missing Contents directory"
        exit 1
    fi

    invalid_entries="$(find "${bundle_path}" -mindepth 1 -maxdepth 1 ! -name 'Contents' -print)"
    if [ -n "${invalid_entries}" ]; then
        echo "❌ Error: Unexpected items found at ${bundle_path} root (only Contents is allowed):"
        echo "${invalid_entries}"
        exit 1
    fi
}

validate_required_resources() {
    local bundle_path="$1"
    local resources_dir="${bundle_path}/Contents/Resources"
    local required_files=(
        "whisper_server"
        "koto-tyoe_banner_transparent.png"
        "koto-type_logo_mini_dark.png"
        "koto-type_logo_mini_light.png"
        "koto-tyoe_logo_dark.png"
        "koto-tyoe_logo_light.png"
    )
    local missing=0

    for relpath in "${required_files[@]}"; do
        if [ ! -f "${resources_dir}/${relpath}" ]; then
            echo "❌ Error: Missing required resource: ${resources_dir}/${relpath}"
            missing=1
        fi
    done

    if [ "${missing}" -ne 0 ]; then
        exit 1
    fi
}
strip_code_signature_if_present() {
    local target_path="$1"

    if codesign -dv "${target_path}" >/dev/null 2>&1; then
        echo "Removing existing code signature: ${target_path}"
        if ! codesign --remove-signature "${target_path}" >/dev/null 2>&1; then
            echo "❌ Error: Failed to remove code signature from ${target_path}"
            exit 1
        fi
    fi
}

ad_hoc_sign() {
    local target_path="$1"

    echo "Ad-hoc signing: ${target_path}"
    if ! codesign --force --sign - "${target_path}"; then
        echo "❌ Error: Failed to ad-hoc sign ${target_path}"
        exit 1
    fi
}

verify_signed_binary() {
    local target_path="$1"
    if ! codesign -dv "${target_path}" >/dev/null 2>&1; then
        echo "❌ Error: ${target_path} is not code signed"
        exit 1
    fi
}

verify_bundle_signature() {
    local bundle_path="$1"
    if ! codesign --verify --deep --strict --verbose=2 "${bundle_path}" >/dev/null 2>&1; then
        echo "❌ Error: Bundle signature verification failed: ${bundle_path}"
        codesign --verify --deep --strict --verbose=4 "${bundle_path}" || true
        exit 1
    fi
}

echo "Creating KotoType.app bundle..."
echo ""
echo "注意: whisper_server バイナリ（dist/whisper_server）が必須です"
echo "未作成の場合: cd .. && make build-server"
echo ""

# 設定
APP_NAME="KotoType"
APP_VERSION="$(./scripts/version.sh)"
BUNDLE_NAME="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_NAME}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="../assets/logo/koto-tyoe_logo_dark.png"
EXECUTABLE_SOURCE=""

if [ -n "${KOTOTYPE_BUILD_CONFIG:-}" ]; then
    CANDIDATE=".build/${KOTOTYPE_BUILD_CONFIG}/${APP_NAME}"
    if [ -f "${CANDIDATE}" ]; then
        EXECUTABLE_SOURCE="${CANDIDATE}"
    fi
else
    for candidate in ".build/release/${APP_NAME}" ".build/debug/${APP_NAME}"; do
        if [ -f "${candidate}" ]; then
            EXECUTABLE_SOURCE="${candidate}"
            break
        fi
    done
fi

if [ -z "${EXECUTABLE_SOURCE}" ]; then
    echo "❌ Error: KotoType executable not found in .build/{release,debug}"
    echo "Please run one of the following commands first:"
    echo "  swift build -c release"
    echo "  swift build"
    exit 1
fi

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
cp "${EXECUTABLE_SOURCE}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
strip_code_signature_if_present "${MACOS_DIR}/${APP_NAME}"

# whisper_serverバイナリをコピー
if [ -f "../dist/whisper_server" ]; then
    echo "Copying whisper_server binary..."
    cp "../dist/whisper_server" "${RESOURCES_DIR}/"
    chmod +x "${RESOURCES_DIR}/whisper_server"
    strip_code_signature_if_present "${RESOURCES_DIR}/whisper_server"
else
    echo "❌ Error: whisper_server binary not found in ../dist/"
    echo "Please run: cd .. && make build-server"
    echo "Note: ffmpeg is intentionally not bundled. Users should install ffmpeg in their environment."
    exit 1
fi

# ロゴ画像をコピー（アプリ内表示向け）
if [ -d "../assets/logo" ]; then
    echo "Copying logo assets..."
    cp "../assets/logo/"*.png "${RESOURCES_DIR}/" 2>/dev/null || true
fi

# SwiftPMリソースバンドルをコピー
RESOURCE_BUNDLE_PATH="$(find .build -type d -name 'KotoType_KotoType.bundle' | head -n 1)"
if [ -n "${RESOURCE_BUNDLE_PATH}" ] && [ -d "${RESOURCE_BUNDLE_PATH}" ]; then
    echo "Copying SwiftPM resource bundle..."
    cp -R "${RESOURCE_BUNDLE_PATH}" "${RESOURCES_DIR}/"
fi

# icnsアイコンを生成（Finder / Applications表示用）
if [ -f "${ICON_SOURCE}" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    echo "Generating app icon (.icns)..."
    ICONSET_ROOT="$(mktemp -d)"
    ICONSET_DIR="${ICONSET_ROOT}/KotoType.iconset"
    mkdir -p "${ICONSET_DIR}"

    sips -z 16 16     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
    sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
    sips -z 64 64     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
    sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
    sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/KotoType.icns"
    rm -rf "${ICONSET_ROOT}"
fi

# Info.plistを作成
echo "Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>KotoType</string>
	<key>CFBundleIdentifier</key>
	<string>com.ymuichiro.kototype</string>
	<key>CFBundleName</key>
	<string>KotoType</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>KotoType.icns</string>
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

# バージョン埋め込み
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${CONTENTS_DIR}/Info.plist"

echo "Applying ad-hoc signatures..."
ad_hoc_sign "${RESOURCES_DIR}/whisper_server"
ad_hoc_sign "${MACOS_DIR}/${APP_NAME}"
ad_hoc_sign "${BUNDLE_NAME}"

echo "Verifying signatures..."
verify_signed_binary "${RESOURCES_DIR}/whisper_server"
verify_signed_binary "${MACOS_DIR}/${APP_NAME}"
verify_bundle_signature "${BUNDLE_NAME}"

echo "Validating app bundle layout..."
validate_app_bundle_layout "${BUNDLE_NAME}"
echo "Validating required app resources..."
validate_required_resources "${BUNDLE_NAME}"

echo "✅ ${BUNDLE_NAME} created successfully!"
echo "Bundle location: $(pwd)/${BUNDLE_NAME}"
echo "Version: ${APP_VERSION}"
echo "Executable source: ${EXECUTABLE_SOURCE}"
echo ""
echo "To launch: open ${BUNDLE_NAME}"
