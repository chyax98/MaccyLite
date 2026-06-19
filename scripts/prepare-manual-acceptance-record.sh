#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/docs/manual-acceptance-record.md"
RECORD="${ROOT}/dist/validation/manual-acceptance-record.md"

cd "${ROOT}"

today="$(date '+%Y-%m-%d')"
macos="$(sw_vers -productVersion)"
machine="$(uname -m)"
commit="$(git rev-parse --short HEAD)"

mkdir -p "$(dirname "${RECORD}")"

python3 - "$TEMPLATE" "$RECORD" "$today" "$macos" "$machine" "$commit" <<'PY'
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
record_path = Path(sys.argv[2])
today = sys.argv[3]
macos = sys.argv[4]
machine = sys.argv[5]
commit = sys.argv[6]

replacements = {
  "- 日期：": f"- 日期：{today}",
  "- macOS：": f"- macOS：{macos}",
  "- 机器：": f"- 机器：{machine}",
  "- Git commit：": f"- Git commit：{commit}",
  "- 构建命令：": "- 构建命令：`scripts/build-local-app.sh`",
  "- 自动证据：": "- 自动证据：`dist/validation/automatic-evidence.md`",
  "- App 路径：": "- App 路径：`dist/local/MaccyLite.app`",
}

source_path = record_path if record_path.exists() else template_path
lines = source_path.read_text().splitlines()
updated = []
for line in lines:
  updated.append(next((value for prefix, value in replacements.items() if line.startswith(prefix)), line))

record_path.write_text("\n".join(updated) + "\n")
PY

echo "${RECORD}"
