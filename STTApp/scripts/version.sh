#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"

if [ -n "${STT_VERSION:-}" ]; then
  echo "${STT_VERSION}"
  exit 0
fi

if [ -f "${VERSION_FILE}" ]; then
  version="$(tr -d '[:space:]' < "${VERSION_FILE}")"
  if [ -n "${version}" ]; then
    echo "${version}"
    exit 0
  fi
fi

echo "1.0.0"
