#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD="${ROOT}/docs/manual-acceptance-record.md"

cd "${ROOT}"

today="$(date '+%Y-%m-%d')"
macos="$(sw_vers -productVersion)"
machine="$(uname -m)"
commit="$(git rev-parse --short HEAD)"

python3 - "$RECORD" "$today" "$macos" "$machine" "$commit" <<'PY'
import sys
from pathlib import Path

record_path = Path(sys.argv[1])
today = sys.argv[2]
macos = sys.argv[3]
machine = sys.argv[4]
commit = sys.argv[5]

replacements = {
  "- 日期：": f"- 日期：{today}",
  "- macOS：": f"- macOS：{macos}",
  "- 机器：": f"- 机器：{machine}",
  "- Git commit：": f"- Git commit：{commit}",
  "- 构建命令：": "- 构建命令：`scripts/build-local-app.sh`",
  "- 自动证据：": "- 自动证据：`dist/validation/automatic-evidence.md`",
  "- App 路径：": "- App 路径：`dist/local/MaccyLite.app`",
  "- 是否复制到 `/Applications`：": "- 是否复制到 `/Applications`：是 / 否",
  "- 验收人：": "- 验收人：",
  "- 总结论：": "- 总结论：通过 / 有问题",
}

lines = record_path.read_text().splitlines()
updated = []
for line in lines:
  updated.append(next((value for prefix, value in replacements.items() if line.startswith(prefix)), line))

record_path.write_text("\n".join(updated) + "\n")
PY

echo "${RECORD}"
