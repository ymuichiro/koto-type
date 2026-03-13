#!/bin/bash
set -euo pipefail

APP_NAME="KotoType"
APP_BUNDLE="${APP_NAME}.app"
APP_VERSION="$(./scripts/version.sh)"
ZIP_NAME="${APP_NAME}-${APP_VERSION}.zip"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "❌ Error: ${APP_BUNDLE} not found"
    echo "Please run ./scripts/create_app.sh first"
    exit 1
fi

echo "Creating update ZIP for ${APP_BUNDLE}..."
rm -f "${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_NAME}"

SIZE="$(du -h "${ZIP_NAME}" | cut -f1)"
echo ""
echo "✅ ZIP created successfully"
echo "File: ${ZIP_NAME}"
echo "Size: ${SIZE}"
