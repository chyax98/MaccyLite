#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${ROOT}/DerivedData/LocalApp"
OUTPUT_DIR="${ROOT}/dist/local"
APP_NAME="MaccyLite.app"
BUILT_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}"
OUTPUT_APP="${OUTPUT_DIR}/${APP_NAME}"

cd "${ROOT}"

rm -rf "${DERIVED_DATA}" "${OUTPUT_APP}"
mkdir -p "${OUTPUT_DIR}"

xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  -quiet

if [[ ! -d "${BUILT_APP}" ]]; then
  echo "built app not found: ${BUILT_APP}" >&2
  exit 1
fi

ditto "${BUILT_APP}" "${OUTPUT_APP}"

codesign --force --deep --sign - "${OUTPUT_APP}"
xattr -dr com.apple.quarantine "${OUTPUT_APP}" 2>/dev/null || true
codesign --verify --deep --strict "${OUTPUT_APP}"

echo "${OUTPUT_APP}"
