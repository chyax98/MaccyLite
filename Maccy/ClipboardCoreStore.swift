import AppKit
import ClipboardCore
import Foundation
import Logging

final class ClipboardCoreStore {
  static let shared = ClipboardCoreStore()

  private let logger = Logger(label: "com.local.MaccyLite.store")
  private let database: ClipboardDatabase
  private let assetStore: ClipboardCore.AssetStore
  private let capture: ClipboardCapture
  private let historyStore: ClipboardHistoryStore
  private let root: URL
  private let trimBatchSize = 50
  private let trimLock = NSLock()
  private let revisionLock = NSLock()
  private var didTrimAfterLaunch = false
  private var insertsSinceTrim = 0
  private var currentRevision = 0

  private init() {
    let root = URL.applicationSupportDirectory.appending(path: "MaccyLite")
    self.root = root
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    } catch {
      logger.error("Failed to create MaccyLite storage directory \(root.path): \(error.localizedDescription)")
    }
    assetStore = ClipboardCore.AssetStore(root: root.appending(path: "Assets"))
    database = try! ClipboardDatabase(path: root.appending(path: "Clipboard.sqlite"))
    capture = ClipboardCapture(assetStore: assetStore)
    historyStore = ClipboardHistoryStore(database: database, capture: capture)
  }

  func insert(
    contents: [ClipboardRawContent],
    sourceApp: String?,
    copiedAt: Date = .now
  ) -> ClipboardStoredItem? {
    do {
      guard let item = try historyStore.insert(contents: contents, sourceApp: sourceApp, copiedAt: copiedAt) else {
        return nil
      }

      if shouldTrimAfterInsert() {
        do {
          try historyStore.trimUnpinned(maxCount: AppPreferences.size)
        } catch {
          logger.error("Failed to trim clipboard history after insert: \(error.localizedDescription)")
        }
      }
      bumpRevision()
      return item
    } catch {
      logger.error("Failed to insert clipboard item: \(error.localizedDescription)")
      return nil
    }
  }

  func latest(limit: Int = 50, offset: Int = 0) -> [ClipboardListItem] {
    do {
      return try historyStore.latestList(limit: limit, offset: offset)
    } catch {
      logger.error("Failed to load latest clipboard items: \(error.localizedDescription)")
      return []
    }
  }

  func search(_ query: String, limit: Int = 50) -> [ClipboardListItem] {
    do {
      return try historyStore.searchList(query, limit: limit)
    } catch {
      logger.error("Failed to search clipboard items for query '\(query)': \(error.localizedDescription)")
      return []
    }
  }

  func item(id: String) -> ClipboardStoredItem? {
    do {
      return try historyStore.selectedItem(id: id)
    } catch {
      logger.error("Failed to load clipboard item \(id): \(error.localizedDescription)")
      return nil
    }
  }

  func setPinned(_ isPinned: Bool, itemID: String) {
    do {
      try historyStore.setPinned(isPinned, itemID: itemID)
      bumpRevision()
    } catch {
      logger.error("Failed to set pinned=\(isPinned) for clipboard item \(itemID): \(error.localizedDescription)")
    }
  }

  func delete(itemID: String) {
    do {
      try historyStore.delete(itemID: itemID)
      bumpRevision()
    } catch {
      logger.error("Failed to delete clipboard item \(itemID): \(error.localizedDescription)")
    }
  }

  func deleteUnpinned() {
    do {
      try historyStore.deleteUnpinned()
      bumpRevision()
    } catch {
      logger.error("Failed to delete unpinned clipboard items: \(error.localizedDescription)")
    }
  }

  func deleteAll() {
    do {
      try historyStore.deleteAll()
      bumpRevision()
    } catch {
      logger.error("Failed to delete clipboard items: \(error.localizedDescription)")
    }
  }

  func latestUnpinnedDisplayText() -> String? {
    do {
      return try historyStore.latestUnpinnedDisplayText()
    } catch {
      logger.error("Failed to load latest clipboard title: \(error.localizedDescription)")
      return nil
    }
  }

  private func shouldTrimAfterInsert() -> Bool {
    trimLock.lock()
    defer { trimLock.unlock() }

    guard didTrimAfterLaunch else {
      didTrimAfterLaunch = true
      insertsSinceTrim = 0
      return true
    }

    insertsSinceTrim += 1
    guard insertsSinceTrim >= trimBatchSize else {
      return false
    }

    insertsSinceTrim = 0
    return true
  }

  var revision: Int {
    revisionLock.lock()
    defer { revisionLock.unlock() }
    return currentRevision
  }

  private func bumpRevision() {
    revisionLock.lock()
    currentRevision += 1
    revisionLock.unlock()
  }

  @discardableResult
  func export(day: Date) throws -> DailyExportResult {
    try dailyExporter().export(day: day)
  }

  func exportRecord(day: Date) -> DailyExportRecord? {
    do {
      return try database.exportRecord(day: day)
    } catch {
      logger.error("Failed to load daily export record for \(day): \(error.localizedDescription)")
      return nil
    }
  }

  func exportItemCount(day: Date, calendar: Calendar = .current) -> Int? {
    let start = calendar.startOfDay(for: day)
    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
      return nil
    }
    do {
      return try database.itemCount(from: start, to: end)
    } catch {
      logger.error("Failed to count daily export items for \(day): \(error.localizedDescription)")
      return nil
    }
  }

  @discardableResult
  func removeOrphanAssets() -> [String] {
    do {
      return try dailyExporter().removeOrphanAssets()
    } catch {
      logger.error("Failed to remove orphan clipboard assets: \(error.localizedDescription)")
      return []
    }
  }

  var storageSize: String {
    let urls = [
      root.appending(path: "Clipboard.sqlite"),
      root.appending(path: "Clipboard.sqlite-wal"),
      root.appending(path: "Clipboard.sqlite-shm"),
      root.appending(path: "Assets")
    ]
    let bytes = urls.reduce(Int64(0)) { partial, url in
      partial + byteCount(at: url)
    }

    guard bytes > 0 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: bytes)
  }

  var exportDirectory: URL {
    return defaultExportDirectory
  }

  func ensureExportDirectoryExists() throws -> URL {
    let directory = exportDirectory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  func data(for content: ClipboardStoredContent) -> Data? {
    if let inlineData = content.inlineData {
      return inlineData
    }

    guard let assetPath = content.assetPath else {
      return nil
    }

    return try? assetStore.read(assetPath)
  }

  func data(assetPath: String) -> Data? {
    try? assetStore.read(assetPath)
  }

  func pasteboardPayload(for item: ClipboardStoredItem, removeFormatting: Bool = false) throws -> [(type: String, data: Data)] {
    let resolver = ClipboardPasteboardPayloadResolver(
      stringType: NSPasteboard.PasteboardType.string.rawValue,
      fileURLType: NSPasteboard.PasteboardType.fileURL.rawValue
    ) { [assetStore] assetPath in
      try assetStore.read(assetPath)
    }

    return try resolver.payloads(for: item, removeFormatting: removeFormatting)
      .map { ($0.pasteboardType, $0.data) }
  }

  private func byteCount(at url: URL) -> Int64 {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return 0
    }

    if !isDirectory.boolValue {
      let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      return Int64(values?.fileSize ?? 0)
    }

    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }

    return enumerator.compactMap { entry -> Int64? in
      guard let url = entry as? URL,
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else {
        return nil
      }
      return Int64(values.fileSize ?? 0)
    }.reduce(0, +)
  }

  private var defaultExportDirectory: URL {
    root.appending(path: "Exports")
  }

  private func dailyExporter() -> DailyExporter {
    DailyExporter(
      database: database,
      assetStore: assetStore,
      exportDirectory: exportDirectory
    )
  }
}
