#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-${ROOT}/dist/validation/automatic-evidence.md}"
LOG_FILE="$(mktemp)"

cd "${ROOT}"

mkdir -p "$(dirname "${OUTPUT}")"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

set +e
scripts/validate-productization.sh 2>&1 | tee "${LOG_FILE}"
STATUS="${PIPESTATUS[0]}"
set -e

FINISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

{
  printf '# Automatic Validation Evidence\n\n'
  printf '| Field | Value |\n'
  printf '| --- | --- |\n'
  printf '| Branch | `%s` |\n' "${BRANCH}"
  printf '| Commit | `%s` |\n' "${COMMIT}"
  printf '| Started at UTC | `%s` |\n' "${STARTED_AT}"
  printf '| Finished at UTC | `%s` |\n' "${FINISHED_AT}"
  printf '| Command | `scripts/validate-productization.sh` |\n'
  printf '| Exit status | `%s` |\n\n' "${STATUS}"

  printf '## Gate Summary\n\n'
  grep -E '^(non-gui validation check passed|maintenance validation passed|performance validation passed|productization validation passed)$' "${LOG_FILE}" || true
  printf '\n## Performance Summary\n\n'
  grep -E '^(mode|items|runs|latest_p95_ms|cjk_search_p95_ms|token_search_p95_ms|pending_thumbnail_jobs_p95_ms|pending_thumbnail_jobs|asset_bytes)=' "${LOG_FILE}" || true
  printf '\n## Full Log\n\n'
  printf '```text\n'
  cat "${LOG_FILE}"
  printf '```\n'
} > "${OUTPUT}"

rm -f "${LOG_FILE}"

if [[ "${STATUS}" != "0" ]]; then
  echo "automatic evidence captured failed validation: ${OUTPUT}" >&2
  exit "${STATUS}"
fi

echo "${OUTPUT}"
