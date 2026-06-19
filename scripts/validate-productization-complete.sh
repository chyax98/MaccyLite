#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "== Automatic validation evidence =="
scripts/write-automatic-evidence.sh

echo "== Manual acceptance record =="
scripts/validate-manual-acceptance-record.py

echo "productization completion validation passed"
