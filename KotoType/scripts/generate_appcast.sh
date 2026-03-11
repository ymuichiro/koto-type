#!/bin/bash
set -euo pipefail

APP_NAME="KotoType"
APP_VERSION="$(./scripts/version.sh)"
ZIP_NAME="${APP_NAME}-${APP_VERSION}.zip"
UPDATES_DIR="${PWD}/sparkle_updates"
OUTPUT_APPCAST="${PWD}/appcast.xml"

if [ ! -f "${ZIP_NAME}" ]; then
    echo "❌ Error: ${ZIP_NAME} not found"
    echo "Please run ./scripts/create_update_zip.sh first"
    exit 1
fi

if [ -z "${KOTOTYPE_SPARKLE_PRIVATE_ED_KEY:-}" ]; then
    echo "❌ Error: KOTOTYPE_SPARKLE_PRIVATE_ED_KEY is required"
    exit 1
fi

if [ -z "${KOTOTYPE_SPARKLE_DOWNLOAD_URL_PREFIX:-}" ]; then
    echo "❌ Error: KOTOTYPE_SPARKLE_DOWNLOAD_URL_PREFIX is required"
    exit 1
fi

GENERATE_APPCAST_BIN="${GENERATE_APPCAST_BIN:-}"
if [ -z "${GENERATE_APPCAST_BIN}" ]; then
    for candidate in \
        "${PWD}/sparkle/bin/generate_appcast" \
        "${PWD}/../build/sparkle/bin/generate_appcast" \
        "${PWD}/../build/sparkle-tools/bin/generate_appcast"; do
        if [ -x "${candidate}" ]; then
            GENERATE_APPCAST_BIN="${candidate}"
            break
        fi
    done
fi

if [ -z "${GENERATE_APPCAST_BIN}" ] || [ ! -x "${GENERATE_APPCAST_BIN}" ]; then
    echo "❌ Error: generate_appcast binary not found."
    echo "Set GENERATE_APPCAST_BIN explicitly or place Sparkle tools under ./sparkle/bin."
    exit 1
fi

SIGN_UPDATE_BIN="${SIGN_UPDATE_BIN:-}"
if [ -z "${SIGN_UPDATE_BIN}" ]; then
    for candidate in \
        "${PWD}/sparkle/bin/sign_update" \
        "${PWD}/../build/sparkle/bin/sign_update" \
        "${PWD}/../build/sparkle-tools/bin/sign_update"; do
        if [ -x "${candidate}" ]; then
            SIGN_UPDATE_BIN="${candidate}"
            break
        fi
    done
fi

if [ -z "${SIGN_UPDATE_BIN}" ] || [ ! -x "${SIGN_UPDATE_BIN}" ]; then
    echo "❌ Error: sign_update binary not found."
    echo "Set SIGN_UPDATE_BIN explicitly or place Sparkle tools under ./sparkle/bin."
    exit 1
fi

echo "Generating Sparkle appcast..."
rm -rf "${UPDATES_DIR}"
mkdir -p "${UPDATES_DIR}"
cp "${ZIP_NAME}" "${UPDATES_DIR}/"

if [ -f "${OUTPUT_APPCAST}" ]; then
    cp "${OUTPUT_APPCAST}" "${UPDATES_DIR}/appcast.xml"
fi

printf '%s' "${KOTOTYPE_SPARKLE_PRIVATE_ED_KEY}" | "${GENERATE_APPCAST_BIN}" \
    --ed-key-file - \
    --download-url-prefix "${KOTOTYPE_SPARKLE_DOWNLOAD_URL_PREFIX}" \
    -o "${UPDATES_DIR}/appcast.xml" \
    "${UPDATES_DIR}"

cp "${UPDATES_DIR}/appcast.xml" "${OUTPUT_APPCAST}"
printf '%s' "${KOTOTYPE_SPARKLE_PRIVATE_ED_KEY}" | "${SIGN_UPDATE_BIN}" --ed-key-file - "${OUTPUT_APPCAST}"
echo "✅ appcast generated: ${OUTPUT_APPCAST}"
