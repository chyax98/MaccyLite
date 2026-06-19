#!/usr/bin/env python3
import re
import subprocess
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
  value = match.group(1).strip()
  if value.startswith("`") and value.endswith("`"):
    value = value[1:-1].strip()
  return value


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


def resolve_record_path(value: str) -> Path:
  path = Path(value).expanduser()
  if not path.is_absolute():
    path = ROOT / path
  return path


def current_commit() -> str:
  try:
    result = subprocess.run(
      ["git", "rev-parse", "--short", "HEAD"],
      cwd=ROOT,
      check=True,
      capture_output=True,
      text=True,
    )
  except (FileNotFoundError, subprocess.CalledProcessError):
    fail("cannot read current git commit")
  return result.stdout.strip()


def markdown_table_value(text: str, field: str) -> str:
  pattern = rf"^\| {re.escape(field)} \| `([^`]+)` \|$"
  match = re.search(pattern, text, re.MULTILINE)
  if not match:
    fail(f"automatic evidence is missing field: {field}")
  return match.group(1).strip()


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

  if line_value(text, "构建命令") != "scripts/build-local-app.sh":
    fail("build command must be scripts/build-local-app.sh")

  record_commit = line_value(text, "Git commit")
  head_commit = current_commit()
  if record_commit != head_commit:
    fail(f"record git commit {record_commit} does not match current commit {head_commit}")

  app_path = resolve_record_path(line_value(text, "App 路径"))
  if not app_path.is_dir():
    fail(f"app path does not exist: {app_path}")

  automatic_evidence_path = resolve_record_path(line_value(text, "自动证据"))
  if not automatic_evidence_path.is_file():
    fail(f"automatic evidence file does not exist: {automatic_evidence_path}")

  automatic_evidence = automatic_evidence_path.read_text(errors="ignore")
  if markdown_table_value(automatic_evidence, "Exit status") != "0":
    fail("automatic evidence exit status is not 0")
  evidence_commit = markdown_table_value(automatic_evidence, "Commit")
  if evidence_commit != record_commit:
    fail(f"automatic evidence commit {evidence_commit} does not match record commit {record_commit}")
  for marker in [
    "non-gui validation check passed",
    "maintenance validation passed",
    "performance validation passed",
    "productization validation passed",
  ]:
    if marker not in automatic_evidence:
      fail(f"automatic evidence is missing marker: {marker}")

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
