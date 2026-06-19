#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
  raise SystemExit(f"non-gui validation check failed: {message}")


def git_tracked_files() -> list[str]:
  try:
    result = subprocess.run(
      ["git", "ls-files"],
      cwd=ROOT,
      check=True,
      capture_output=True,
      text=True,
    )
  except (FileNotFoundError, subprocess.CalledProcessError):
    return []
  return result.stdout.splitlines()


for tracked_path in git_tracked_files():
  if (
    tracked_path == ".build"
    or tracked_path.startswith(".build/")
    or tracked_path == "ClipboardCore/.build"
    or tracked_path.startswith("ClipboardCore/.build/")
    or tracked_path == "DerivedData"
    or tracked_path.startswith("DerivedData/")
    or tracked_path.endswith(".xcuserstate")
    or ".xcuserdata/" in tracked_path
  ):
    fail(f"generated file is tracked by git: {tracked_path}")


testplan = json.loads((ROOT / "Maccy.xctestplan").read_text())
if testplan.get("testTargets") != []:
  fail("Maccy.xctestplan must not contain test targets")

pbxproj = (ROOT / "Maccy.xcodeproj/project.pbxproj").read_text()
for forbidden in [
  "MaccyUITests",
  "com.apple.product-type.bundle.ui-testing",
  "TEST_TARGET_NAME",
  "History.xcdatamodeld",
  "Storage.xcdatamodeld",
  "SoftwareUpdater.swift",
  "AppStoreReview.swift",
  "Notifier.swift",
]:
  if forbidden in pbxproj:
    fail(f"Xcode project still contains {forbidden}")

for forbidden_path in [
  ".github",
  "Designs",
  "MaccyTests",
  "MaccyUITests",
  "Maccy/History.xcdatamodeld",
  "Maccy/Storage.xcdatamodeld",
  "Maccy/Intents",
  "Maccy/Sounds",
  "Maccy/AppStoreReview.swift",
  "Maccy/SoftwareUpdater.swift",
  "Maccy/Notifier.swift",
  "Maccy/Search.swift",
  "Maccy/Sorter.swift",
  "Maccy/Storage.swift",
]:
  if (ROOT / forbidden_path).exists():
    fail(f"{forbidden_path} should not exist")

lproj_paths = sorted((ROOT / "Maccy").rglob("*.lproj"))
non_chinese_lproj = [
  str(path.relative_to(ROOT))
  for path in lproj_paths
  if path.name != "zh-Hans.lproj"
]
if non_chinese_lproj:
  fail(f"non zh-Hans localization directories remain: {', '.join(non_chinese_lproj)}")

for source_root in ["Maccy", "ClipboardCore"]:
  for path in (ROOT / source_root).rglob("*.swift"):
    if ".build" in path.parts or not path.is_file():
      continue
    text = path.read_text(errors="ignore")
    for forbidden in ["XCUIApplication", "enable-testing"]:
      if forbidden in text:
        fail(f"{path.relative_to(ROOT)} still contains {forbidden}")

for path in (ROOT / "ClipboardCore/Tests").rglob("*.swift"):
  text = path.read_text(errors="ignore")
  for forbidden in [
    "NSApplication",
    "NSPasteboard.general",
    "CGEvent",
    "AXUIElement",
    "Accessibility.check",
    ".launch(",
  ]:
    if forbidden in text:
      fail(f"{path.relative_to(ROOT)} contains desktop API token {forbidden}")

for docs_root in ["README.md", "docs"]:
  root = ROOT / docs_root
  paths = [root] if root.is_file() else list(root.rglob("*"))
  for path in paths:
    if not path.is_file():
      continue
    text = path.read_text(errors="ignore")
    for forbidden in [
      "xcodebuild test",
      "build-for-testing",
      "XCUIApplication",
      "osascript",
      "System Events",
    ]:
      if forbidden in text:
        fail(f"{path.relative_to(ROOT)} mentions forbidden GUI/e2e validation token {forbidden}")

print("non-gui validation check passed")
