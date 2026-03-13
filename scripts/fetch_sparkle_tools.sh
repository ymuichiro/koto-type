#!/bin/bash
set -euo pipefail

SPARKLE_VERSION="${1:-2.9.0}"
OUTPUT_DIR="${2:-build/sparkle-tools}"
ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

echo "Fetching Sparkle tools ${SPARKLE_VERSION}..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -L -o "${TMP_DIR}/Sparkle.tar.xz" "${ARCHIVE_URL}"
tar -xf "${TMP_DIR}/Sparkle.tar.xz" -C "${TMP_DIR}"
cp -R "${TMP_DIR}/bin" "${OUTPUT_DIR}/"

if [ ! -x "${OUTPUT_DIR}/bin/generate_appcast" ]; then
    echo "❌ Error: generate_appcast not found in fetched Sparkle tools"
    exit 1
fi

echo "✅ Sparkle tools installed to ${OUTPUT_DIR}"
