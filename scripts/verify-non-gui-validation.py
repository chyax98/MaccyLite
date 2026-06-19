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


def require_file(path: str) -> str:
  file_path = ROOT / path
  if not file_path.is_file():
    fail(f"required file is missing: {path}")
  return file_path.read_text(errors="ignore")


def require_executable(path: str) -> None:
  file_path = ROOT / path
  if not file_path.is_file():
    fail(f"required executable is missing: {path}")
  if not file_path.stat().st_mode & 0o111:
    fail(f"required executable is not executable: {path}")


def require_text(path: str, *snippets: str) -> None:
  text = require_file(path)
  for snippet in snippets:
    if snippet not in text:
      fail(f"{path} must mention {snippet}")


def strings_keys(path: Path) -> set[str]:
  text = path.read_text(errors="ignore")
  return set(re.findall(r'^\s*"((?:\\.|[^"\\])*)"\s*=', text, re.MULTILINE))


def require_localized_key(table_name: str, key: str, source_path: Path) -> None:
  candidates = sorted((ROOT / "Maccy").rglob(f"zh-Hans.lproj/{table_name}.strings"))
  if not candidates:
    fail(f"{source_path.relative_to(ROOT)} references missing zh-Hans table {table_name}")
  if len(candidates) > 1:
    fail(f"multiple zh-Hans tables named {table_name}: {', '.join(str(path.relative_to(ROOT)) for path in candidates)}")

  if key not in strings_keys(candidates[0]):
    fail(f"{source_path.relative_to(ROOT)} references missing localization key {table_name}.{key}")


def verify_static_localization_references() -> None:
  patterns = [
    re.compile(r'Text\(\s*"([^"]+)"\s*,\s*tableName:\s*"([^"]+)"'),
    re.compile(r'NSLocalizedString\(\s*"([^"]+)"\s*,\s*tableName:\s*"([^"]+)"'),
    re.compile(r'String\(localized:\s*"([^"]+)"\s*,\s*table:\s*"([^"]+)"'),
  ]
  localizable_patterns = [
    re.compile(r'SearchFieldView\(\s*placeholder:\s*"([^"]+)"'),
    re.compile(r'\b(?:title|help|message|comment|confirm|cancel):\s*"([a-z][a-z0-9_]+)"'),
  ]

  for path in (ROOT / "Maccy").rglob("*.swift"):
    if ".build" in path.parts or not path.is_file():
      continue
    text = path.read_text(errors="ignore")
    for pattern in patterns:
      for key, table_name in pattern.findall(text):
        require_localized_key(table_name, key, path)
    for pattern in localizable_patterns:
      for key in pattern.findall(text):
        require_localized_key("Localizable", key, path)


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

require_text(
  "README.md",
  "scripts/validate-productization.sh",
  "FULL_PERFORMANCE=1 scripts/validate-productization.sh",
  "docs/manual-acceptance.md",
)
require_text(
  "docs/release-notes.md",
  "Existing Maccy clipboard history is not migrated.",
  "Existing Maccy settings are not migrated.",
  "~/Library/Application Support/MaccyLite/",
  "scripts/validate-productization.sh",
  "FULL_PERFORMANCE=1 scripts/validate-productization.sh",
)
require_text(
  "docs/productization-acceptance-matrix.md",
  "docs/manual-acceptance.md",
  "scripts/validate-productization.sh",
  "scripts/validate-non-gui.sh",
  "scripts/validate-maintenance.sh",
  "scripts/validate-performance.sh",
  "FULL_PERFORMANCE=1",
  "不迁移旧历史和设置",
)
require_text(
  "docs/benchmark-report.md",
  "FULL_PERFORMANCE=1 scripts/validate-productization.sh",
  "latest page p95 <= `20 ms`",
  "CJK search p95 <= `50 ms`",
  "mixed benchmark must create asset files and pending thumbnail jobs",
)
require_text(
  "docs/development.md",
  "scripts/validate-productization.sh",
  "FULL_PERFORMANCE=1 scripts/validate-productization.sh",
  "scripts/validate-non-gui.sh",
  "scripts/validate-maintenance.sh",
)
require_text(
  "docs/manual-acceptance.md",
  "## 验收记录",
  "- [ ]",
  "Accessibility",
  "Clipboard capture sample",
  "复制失败",
  "每日导出失败",
)
require_executable("scripts/validate-productization.sh")
require_executable("scripts/validate-non-gui.sh")
require_executable("scripts/validate-maintenance.sh")
require_executable("scripts/validate-performance.sh")
verify_static_localization_references()

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
    for marker in ["TODO", "FIXME"]:
      if marker in text:
        fail(f"{path.relative_to(ROOT)} still contains {marker}")

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
