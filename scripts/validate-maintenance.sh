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

fixture_asset_path="2026/06/19/fixture.txt"
fixture_asset_file="$asset_root/$fixture_asset_path"
mkdir -p "$(dirname "$fixture_asset_file")"
printf 'CLI fixture full text\nterminal-token\n' > "$fixture_asset_file"

python3 - "$sqlite_path" "$fixture_asset_path" <<'PY'
import datetime
import sqlite3
import sys

sqlite_path, asset_path = sys.argv[1], sys.argv[2]
copied_at = datetime.datetime(2026, 6, 19, 12, 0, 0).timestamp()
display_text = "CLI fixture terminal-token"
search_text = "CLI fixture terminal-token 数据库维护"
inline_data = display_text.encode("utf-8")

connection = sqlite3.connect(sqlite_path)
try:
  connection.execute(
    """
    INSERT INTO clipboard_items
      (id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count)
    VALUES
      (?, ?, ?, ?, ?, ?, 0, 1)
    """,
    ("fixture-item", copied_at, "tests.maintenance", "public.utf8-plain-text", display_text, search_text),
  )
  connection.execute(
    """
    INSERT INTO clipboard_contents
      (item_id, pasteboard_type, byte_count, inline_data, asset_path, content_hash)
    VALUES
      (?, ?, ?, ?, ?, ?)
    """,
    (
      "fixture-item",
      "public.utf8-plain-text",
      len(inline_data),
      inline_data,
      asset_path,
      "fixture-hash",
    ),
  )
  connection.execute(
    "INSERT INTO clipboard_search(item_id, text) VALUES (?, ?)",
    ("fixture-item", search_text),
  )
  connection.execute(
    "INSERT INTO clipboard_trigram(item_id, text) VALUES (?, ?)",
    ("fixture-item", search_text),
  )
  connection.commit()
finally:
  connection.close()
PY

fixture_health_output="$(run_maintenance health "$sqlite_path")"
assert_contains "$fixture_health_output" "healthy=true"
assert_contains "$fixture_health_output" "items=1"
assert_contains "$fixture_health_output" "contents=1"
assert_contains "$fixture_health_output" "search_index_rows=1"
assert_contains "$fixture_health_output" "trigram_index_rows=1"

fixture_search_output="$(run_maintenance search "$sqlite_path" "terminal-token")"
assert_contains "$fixture_search_output" "results=1"
assert_contains "$fixture_search_output" "fixture-item"

fixture_export_output="$(run_maintenance export "$sqlite_path" "$asset_root" "$export_dir" "$export_day")"
assert_contains "$fixture_export_output" "items=1"
if ! grep -Fq -- "CLI fixture full text" "$export_file"; then
  printf 'maintenance validation failed: fixture export did not include asset full text\n' >&2
  exit 1
fi

fixture_assets_output="$(run_maintenance assets "$sqlite_path" "$asset_root")"
assert_contains "$fixture_assets_output" "healthy=true"
assert_contains "$fixture_assets_output" "referenced=1"
assert_contains "$fixture_assets_output" "existing=1"
assert_contains "$fixture_assets_output" "missing=0"
assert_contains "$fixture_assets_output" "orphaned=0"

fixture_cleanup_output="$(run_maintenance cleanup-assets "$sqlite_path" "$asset_root" --apply)"
assert_contains "$fixture_cleanup_output" "removed=0"
if [[ ! -f "$fixture_asset_file" ]]; then
  printf 'maintenance validation failed: referenced fixture asset was removed\n' >&2
  exit 1
fi

echo "maintenance validation passed"
