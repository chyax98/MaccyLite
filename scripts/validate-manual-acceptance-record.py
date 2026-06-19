#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RECORD = ROOT / "docs/manual-acceptance-record.md"


def fail(message: str) -> None:
  raise SystemExit(f"manual acceptance record validation failed: {message}")


def line_value(text: str, label: str) -> str:
  pattern = rf"^- {re.escape(label)}：\s*(.*)$"
  match = re.search(pattern, text, re.MULTILINE)
  if not match:
    fail(f"missing build field: {label}")
  return match.group(1).strip()


def require_filled(text: str, label: str) -> None:
  value = line_value(text, label)
  if not value:
    fail(f"build field is empty: {label}")
  if value in {"是 / 否", "通过 / 有问题"}:
    fail(f"build field still contains placeholder choice: {label}")


def result_rows(text: str) -> list[tuple[str, str, str]]:
  rows = []
  in_matrix = False
  for line in text.splitlines():
    if line == "## Result Matrix":
      in_matrix = True
      continue
    if in_matrix and line.startswith("## "):
      break
    if not in_matrix or not line.startswith("|"):
      continue
    columns = [column.strip() for column in line.strip("|").split("|")]
    if len(columns) != 3 or columns[0] in {"范围", "---"}:
      continue
    rows.append((columns[0], columns[1], columns[2]))
  return rows


def main() -> None:
  path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_RECORD
  if not path.is_file():
    fail(f"record file not found: {path}")

  text = path.read_text(errors="ignore")

  for label in [
    "日期",
    "macOS",
    "机器",
    "Git commit",
    "构建命令",
    "自动证据",
    "App 路径",
    "是否复制到 `/Applications`",
    "验收人",
    "总结论",
  ]:
    require_filled(text, label)

  if line_value(text, "总结论") != "通过":
    fail("summary conclusion must be 通过")

  rows = result_rows(text)
  if not rows:
    fail("result matrix has no rows")

  for scope, result, evidence in rows:
    if result == "未验收":
      fail(f"scope is not accepted yet: {scope}")
    if result != "通过":
      fail(f"scope did not pass: {scope} = {result}")
    if not evidence:
      fail(f"scope is missing evidence: {scope}")

  print("manual acceptance record validation passed")


if __name__ == "__main__":
  main()
