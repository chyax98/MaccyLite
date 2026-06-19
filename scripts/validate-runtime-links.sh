#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="${APP_PATH:-dist/local/MaccyLite.app}"

if [[ ! -x "${APP_PATH}/Contents/MacOS/MaccyLite" ]]; then
  APP_PATH="$(scripts/build-local-app.sh)"
fi

binary="${APP_PATH}/Contents/MacOS/MaccyLite"
linked="$(otool -L "${binary}")"
for forbidden in SwiftUI DeveloperToolsSupport Defaults KeyboardShortcuts Settings LaunchAtLogin SwiftHEXColors Observation; do
  if grep -q "${forbidden}" <<<"${linked}"; then
    echo "forbidden runtime dependency found: ${forbidden}" >&2
    echo "${linked}" >&2
    exit 1
  fi
done

echo "runtime links validation passed"
