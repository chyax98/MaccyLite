import AppKit
import Foundation

struct StorageType {
  static let files = StorageType(types: [NSPasteboard.PasteboardType.fileURL])
  static let text = StorageType(types: [
    NSPasteboard.PasteboardType.html,
    NSPasteboard.PasteboardType.rtf,
    NSPasteboard.PasteboardType.string
  ])
  static let all = StorageType(types: files.types + text.types)
  static let defaultEnabled = StorageType(types: files.types + text.types)

  var types: [NSPasteboard.PasteboardType]
}

enum AppPreferences {
  private static let defaults = UserDefaults.standard
  private static let captureDefaultsVersionKey = "captureDefaultsVersion"
  private static let currentCaptureDefaultsVersion = 1

  static func migratePerformanceDefaults() {
    guard integer(captureDefaultsVersionKey, 0) < currentCaptureDefaultsVersion else {
      return
    }

    let oldDefault = Set(StorageType.all.types.map(\.rawValue))
    let currentRaw = Set(defaults.stringArray(forKey: "enabledPasteboardTypes") ?? [])
    if currentRaw == oldDefault {
      enabledPasteboardTypes = Set(StorageType.defaultEnabled.types)
    }

    set(currentCaptureDefaultsVersion, captureDefaultsVersionKey)
  }

  static var clearOnQuit: Bool {
    get { bool("clearOnQuit", false) }
    set { set(newValue, "clearOnQuit") }
  }

  static var clearSystemClipboard: Bool {
    get { bool("clearSystemClipboard", false) }
    set { set(newValue, "clearSystemClipboard") }
  }

  static var clipboardCheckInterval: TimeInterval {
    get { double("clipboardCheckInterval", 0.5) }
    set { set(newValue, "clipboardCheckInterval") }
  }

  static var enabledPasteboardTypes: Set<NSPasteboard.PasteboardType> {
    get {
      let raw = defaults.stringArray(forKey: "enabledPasteboardTypes") ?? StorageType.defaultEnabled.types.map { $0.rawValue }
      return Set(raw.map { NSPasteboard.PasteboardType($0) })
        .intersection(Set(StorageType.all.types))
    }
    set { set(newValue.map { $0.rawValue }, "enabledPasteboardTypes") }
  }

  static var dailyExportCatchUpDays: Int {
    get { integer("dailyExportCatchUpDays", 7) }
    set { set(newValue, "dailyExportCatchUpDays") }
  }

  static var dailyExportCleanupOrphans: Bool {
    get { bool("dailyExportCleanupOrphans", true) }
    set { set(newValue, "dailyExportCleanupOrphans") }
  }

  static var dailyExportEnabled: Bool {
    get { bool("dailyExportEnabled", false) }
    set { set(newValue, "dailyExportEnabled") }
  }

  static var dailyExportHour: Int {
    get { integer("dailyExportHour", 0) }
    set { set(newValue, "dailyExportHour") }
  }

  static var dailyExportMinute: Int {
    get { integer("dailyExportMinute", 5) }
    set { set(newValue, "dailyExportMinute") }
  }

  static var ignoreAllAppsExceptListed: Bool {
    get { bool("ignoreAllAppsExceptListed", false) }
    set { set(newValue, "ignoreAllAppsExceptListed") }
  }

  static var ignoreEvents: Bool {
    get { bool("ignoreEvents", false) }
    set { set(newValue, "ignoreEvents") }
  }

  static var ignoreOnlyNextEvent: Bool {
    get { bool("ignoreOnlyNextEvent", false) }
    set { set(newValue, "ignoreOnlyNextEvent") }
  }

  static var ignoreRegexp: [String] {
    get { defaults.stringArray(forKey: "ignoreRegexp") ?? [] }
    set { set(newValue, "ignoreRegexp") }
  }

  static var ignoredApps: [String] {
    get { defaults.stringArray(forKey: "ignoredApps") ?? [] }
    set { set(newValue, "ignoredApps") }
  }

  static var ignoredPasteboardTypes: Set<String> {
    get {
      Set(defaults.stringArray(forKey: "ignoredPasteboardTypes") ?? [
        "Pasteboard generator type",
        "com.agilebits.onepassword",
        "com.typeit4me.clipping",
        "de.petermaurer.TransientPasteboardType",
        "net.antelle.keeweb"
      ])
    }
    set { set(Array(newValue), "ignoredPasteboardTypes") }
  }

  static var imageMaxHeight: Int {
    get { integer("imageMaxHeight", 40) }
    set { set(newValue, "imageMaxHeight") }
  }

  static var menuIcon: MenuIcon {
    get { MenuIcon(rawValue: string("menuIcon", MenuIcon.maccy.rawValue)) ?? .maccy }
    set { set(newValue.rawValue, "menuIcon") }
  }

  static var pasteByDefault: Bool {
    get { bool("pasteByDefault", false) }
    set { set(newValue, "pasteByDefault") }
  }

  static var pinTo: PinsPosition {
    get { PinsPosition(rawValue: string("pinTo", PinsPosition.top.rawValue)) ?? .top }
    set { set(newValue.rawValue, "pinTo") }
  }

  static var popupPosition: PopupPosition {
    get { PopupPosition(rawValue: string("popupPosition", PopupPosition.cursor.rawValue)) ?? .cursor }
    set { set(newValue.rawValue, "popupPosition") }
  }

  static var popupScreen: Int {
    get { integer("popupScreen", 0) }
    set { set(newValue, "popupScreen") }
  }

  static var removeFormattingByDefault: Bool {
    get { bool("removeFormattingByDefault", false) }
    set { set(newValue, "removeFormattingByDefault") }
  }

  static var showInStatusBar: Bool {
    get { bool("showInStatusBar", true) }
    set { set(newValue, "showInStatusBar") }
  }

  static var showRecentCopyInMenuBar: Bool {
    get { bool("showRecentCopyInMenuBar", false) }
    set { set(newValue, "showRecentCopyInMenuBar") }
  }

  static var size: Int {
    get { integer("historySize", 10_000) }
    set { set(newValue, "historySize") }
  }

  static var windowSize: NSSize {
    get {
      let width = double("windowSize.width", 450)
      let height = double("windowSize.height", 800)
      return NSSize(width: width, height: height)
    }
    set {
      set(newValue.width, "windowSize.width")
      set(newValue.height, "windowSize.height")
    }
  }

  static var windowPosition: NSPoint {
    get {
      NSPoint(x: double("windowPosition.x", 0.5), y: double("windowPosition.y", 0.8))
    }
    set {
      set(newValue.x, "windowPosition.x")
      set(newValue.y, "windowPosition.y")
    }
  }

  private static func bool(_ key: String, _ fallback: Bool) -> Bool {
    defaults.object(forKey: key) as? Bool ?? fallback
  }

  private static func integer(_ key: String, _ fallback: Int) -> Int {
    defaults.object(forKey: key) as? Int ?? fallback
  }

  private static func double(_ key: String, _ fallback: Double) -> Double {
    defaults.object(forKey: key) as? Double ?? fallback
  }

  private static func string(_ key: String, _ fallback: String) -> String {
    defaults.string(forKey: key) ?? fallback
  }

  private static func set(_ value: Any, _ key: String) {
    defaults.set(value, forKey: key)
  }
}
