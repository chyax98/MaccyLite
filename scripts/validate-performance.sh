#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

TEXT_ITEMS="${TEXT_ITEMS:-20000}"
MIXED_ITEMS="${MIXED_ITEMS:-3000}"
RUNS="${RUNS:-10}"
LATEST_P95_MAX_MS="${LATEST_P95_MAX_MS:-20}"
SEARCH_P95_MAX_MS="${SEARCH_P95_MAX_MS:-50}"
THUMBNAIL_P95_MAX_MS="${THUMBNAIL_P95_MAX_MS:-50}"

run_benchmark() {
  local items="$1"
  local mode="$2"
  swift run --package-path ClipboardCore -c release clipboard-benchmark "$items" "$mode" --runs "$RUNS"
}

metric() {
  local output="$1"
  local key="$2"
  awk -F= -v wanted="$key" '$1 == wanted { print $2; exit }' <<<"$output"
}

assert_number_le() {
  local name="$1"
  local value="$2"
  local max="$3"
  awk -v name="$name" -v value="$value" -v max="$max" '
    BEGIN {
      if (value == "" || value + 0 > max + 0) {
        printf("performance validation failed: %s=%s > %s\n", name, value, max) > "/dev/stderr"
        exit 1
      }
    }
  '
}

assert_number_gt() {
  local name="$1"
  local value="$2"
  local min="$3"
  awk -v name="$name" -v value="$value" -v min="$min" '
    BEGIN {
      if (value == "" || value + 0 <= min + 0) {
        printf("performance validation failed: %s=%s <= %s\n", name, value, min) > "/dev/stderr"
        exit 1
      }
    }
  '
}

validate_common_query_metrics() {
  local output="$1"
  local prefix="$2"

  assert_number_le "${prefix}_latest_p95_ms" "$(metric "$output" latest_p95_ms)" "$LATEST_P95_MAX_MS"
  assert_number_le "${prefix}_cjk_search_p95_ms" "$(metric "$output" cjk_search_p95_ms)" "$SEARCH_P95_MAX_MS"
  assert_number_le "${prefix}_token_search_p95_ms" "$(metric "$output" token_search_p95_ms)" "$SEARCH_P95_MAX_MS"
  assert_number_le "${prefix}_pending_thumbnail_jobs_p95_ms" "$(metric "$output" pending_thumbnail_jobs_p95_ms)" "$THUMBNAIL_P95_MAX_MS"
}

echo "Running text benchmark: items=$TEXT_ITEMS runs=$RUNS"
text_output="$(run_benchmark "$TEXT_ITEMS" text)"
printf '%s\n' "$text_output"
validate_common_query_metrics "$text_output" text

echo "Running mixed benchmark: items=$MIXED_ITEMS runs=$RUNS"
mixed_output="$(run_benchmark "$MIXED_ITEMS" mixed)"
printf '%s\n' "$mixed_output"
validate_common_query_metrics "$mixed_output" mixed
assert_number_gt "mixed_asset_bytes" "$(metric "$mixed_output" asset_bytes)" 0
assert_number_gt "mixed_pending_thumbnail_jobs" "$(metric "$mixed_output" pending_thumbnail_jobs)" 0

echo "performance validation passed"
