# Release Notes

## MaccyLite Initial Internal Build

MaccyLite is treated as a new self-use application derived from Maccy, not as an in-place upgrade of upstream Maccy.

### Data Compatibility

- Existing Maccy clipboard history is not migrated.
- Existing Maccy settings are not migrated.
- Existing Maccy SwiftData/CoreData stores are not read on startup.
- MaccyLite uses its own Application Support directory:

```text
~/Library/Application Support/MaccyLite/
├── Clipboard.sqlite
├── Assets/
└── Exports/
```

This avoids startup-time migration risk and keeps the new SQLite/asset-store architecture clean. If old Maccy history ever needs to be imported, treat it as a separate one-shot import tool, not as product startup compatibility code.

### Removed Scope

- OCR / Vision.
- Sparkle updater.
- AppIntents / Shortcuts.
- Notification sounds.
- App Store and multi-language release material.
- SwiftData history storage.
- GUI/XCUITest automation path.

### Validation Before Use

Run:

```sh
scripts/validate-non-gui.sh
scripts/validate-performance.sh
```

Then complete `docs/manual-acceptance.md` in a real macOS session.
