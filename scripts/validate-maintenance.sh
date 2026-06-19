#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sqlite_path="$tmp_dir/Clipboard.sqlite"
asset_root="$tmp_dir/Assets"
export_dir="$tmp_dir/Exports"
export_day="2026-06-19"

run_maintenance() {
  swift run --package-path ClipboardCore -c release clipboard-maintenance "$@"
}

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'maintenance validation failed: expected output to contain %s\n' "$expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

health_output="$(run_maintenance health "$sqlite_path")"
assert_contains "$health_output" "healthy=true"
assert_contains "$health_output" "items=0"
assert_contains "$health_output" "contents=0"

reindex_output="$(run_maintenance reindex "$sqlite_path")"
assert_contains "$reindex_output" "healthy=true"

search_output="$(run_maintenance search "$sqlite_path" "不存在的关键词")"
assert_contains "$search_output" "results=0"

export_output="$(run_maintenance export "$sqlite_path" "$asset_root" "$export_dir" "$export_day")"
assert_contains "$export_output" "day=$export_day"
assert_contains "$export_output" "items=0"

export_file="$export_dir/$export_day.md"
if [[ ! -f "$export_file" ]]; then
  printf 'maintenance validation failed: export file missing: %s\n' "$export_file" >&2
  exit 1
fi
if ! grep -Fq -- "- 条目数：0" "$export_file"; then
  printf 'maintenance validation failed: export file did not record empty item count\n' >&2
  exit 1
fi

assets_output="$(run_maintenance assets "$sqlite_path" "$asset_root")"
assert_contains "$assets_output" "healthy=true"
assert_contains "$assets_output" "missing=0"
assert_contains "$assets_output" "orphaned=0"

cleanup_output="$(run_maintenance cleanup-assets "$sqlite_path" "$asset_root")"
assert_contains "$cleanup_output" "would_remove=0"

cleanup_apply_output="$(run_maintenance cleanup-assets "$sqlite_path" "$asset_root" --apply)"
assert_contains "$cleanup_apply_output" "removed=0"

echo "maintenance validation passed"
