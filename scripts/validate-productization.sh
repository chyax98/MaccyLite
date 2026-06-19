#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== Non-GUI validation =="
scripts/validate-non-gui.sh

echo "== Maintenance CLI validation =="
scripts/validate-maintenance.sh

if [[ "${FULL_PERFORMANCE:-0}" == "1" ]]; then
  export TEXT_ITEMS="${TEXT_ITEMS:-100000}"
  export MIXED_ITEMS="${MIXED_ITEMS:-10000}"
  export RUNS="${RUNS:-20}"
else
  export TEXT_ITEMS="${TEXT_ITEMS:-20000}"
  export MIXED_ITEMS="${MIXED_ITEMS:-3000}"
  export RUNS="${RUNS:-10}"
fi

echo "== Performance validation =="
scripts/validate-performance.sh

echo "productization validation passed"
