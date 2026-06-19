#!/usr/bin/env python3
import json
import re
import subprocess
import xml.etree.ElementTree as ET
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

scheme = ET.parse(ROOT / "Maccy.xcodeproj/xcshareddata/xcschemes/Maccy.xcscheme")
if scheme.findall(".//TestableReference"):
  fail("Maccy.xcscheme must not contain TestableReference entries")

buildable_names = [
  element.get("BlueprintName")
  for element in scheme.findall(".//BuildableReference")
  if element.get("BlueprintName")
]
if sorted(set(buildable_names)) != ["Maccy"]:
  fail(f"Maccy.xcscheme must only reference the Maccy app target: {buildable_names}")

pbxproj = (ROOT / "Maccy.xcodeproj/project.pbxproj").read_text()
for forbidden in [
  "MaccyUITests",
  "com.apple.product-type.bundle.ui-testing",
  "com.apple.product-type.bundle.unit-test",
  "TEST_TARGET_NAME",
  "History.xcdatamodeld",
  "Storage.xcdatamodeld",
  "SoftwareUpdater.swift",
  "AppStoreReview.swift",
  "Notifier.swift",
  "SwiftData",
  "Vision.framework",
  "Sparkle",
  "AppIntents",
]:
  if forbidden in pbxproj:
    fail(f"Xcode project still contains {forbidden}")

native_target_count = len(re.findall(r"isa = PBXNativeTarget;", pbxproj))
if native_target_count != 1:
  fail(f"Xcode project must contain exactly one native target, found {native_target_count}")

product_types = re.findall(r'productType = "([^"]+)";', pbxproj)
if product_types != ["com.apple.product-type.application"]:
  fail(f"Xcode project must only build the app target, found product types: {product_types}")

package_manifest = (ROOT / "ClipboardCore/Package.swift").read_text()
if "GRDB.swift.git" not in package_manifest:
  fail("ClipboardCore package must keep GRDB as the explicit SQLite dependency")

for forbidden in [
  "Sparkle",
  "SwiftData",
  "Vision",
  "AppIntents",
  "KeyboardShortcuts",
  "Defaults",
]:
  if forbidden in package_manifest:
    fail(f"ClipboardCore package manifest should not depend on app/UI package {forbidden}")

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
    for forbidden_import in [
      "SwiftData",
      "Vision",
      "Sparkle",
      "AppIntents",
      "UserNotifications",
    ]:
      if re.search(rf"^\s*import\s+{re.escape(forbidden_import)}\b", text, re.MULTILINE):
        fail(f"{path.relative_to(ROOT)} imports removed framework {forbidden_import}")

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
