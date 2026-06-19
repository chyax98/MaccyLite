#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${ROOT}/DerivedData/LocalApp"
OUTPUT_DIR="${ROOT}/dist/local"
APP_NAME="MaccyLite.app"
BUILT_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}"
OUTPUT_APP="${OUTPUT_DIR}/${APP_NAME}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

cd "${ROOT}"

rm -rf "${DERIVED_DATA}" "${OUTPUT_APP}"
mkdir -p "${OUTPUT_DIR}"

xcodebuild \
  -jobs 2 \
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

bundle_name="$("${PLIST_BUDDY}" -c 'Print :CFBundleName' "${OUTPUT_APP}/Contents/Info.plist")"
bundle_identifier="$("${PLIST_BUDDY}" -c 'Print :CFBundleIdentifier' "${OUTPUT_APP}/Contents/Info.plist")"
lsui_element="$("${PLIST_BUDDY}" -c 'Print :LSUIElement' "${OUTPUT_APP}/Contents/Info.plist")"
minimum_system="$("${PLIST_BUDDY}" -c 'Print :LSMinimumSystemVersion' "${OUTPUT_APP}/Contents/Info.plist")"

if [[ "${bundle_name}" != "MaccyLite" ]]; then
  echo "unexpected CFBundleName: ${bundle_name}" >&2
  exit 1
fi

if [[ "${bundle_identifier}" != "com.local.MaccyLite" ]]; then
  echo "unexpected CFBundleIdentifier: ${bundle_identifier}" >&2
  exit 1
fi

if [[ "${lsui_element}" != "true" ]]; then
  echo "unexpected LSUIElement: ${lsui_element}" >&2
  exit 1
fi

if [[ "${minimum_system}" != "14.0" ]]; then
  echo "unexpected LSMinimumSystemVersion: ${minimum_system}" >&2
  exit 1
fi

echo "${OUTPUT_APP}"
