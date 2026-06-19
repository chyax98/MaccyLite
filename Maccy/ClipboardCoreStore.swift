import AppKit
import ClipboardCore
import Defaults
import Foundation

final class ClipboardCoreStore {
  static let shared = ClipboardCoreStore()

  private let database: ClipboardDatabase
  private let assetStore: ClipboardCore.AssetStore
  private let capture: ClipboardCapture
  private let historyStore: ClipboardHistoryStore
  private let root: URL

  private init() {
    let root = URL.applicationSupportDirectory.appending(path: "MaccyLite")
    self.root = root
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
    guard let item = try? historyStore.insert(contents: contents, sourceApp: sourceApp, copiedAt: copiedAt) else {
      return nil
    }

    try? historyStore.trimUnpinned(maxCount: Defaults[.size])
    return item
  }

  func latest(limit: Int = 50, offset: Int = 0) -> [ClipboardListItem] {
    (try? historyStore.latestList(limit: limit, offset: offset)) ?? []
  }

  func search(_ query: String, limit: Int = 50) -> [ClipboardListItem] {
    (try? historyStore.searchList(query, limit: limit)) ?? []
  }

  func item(id: String) -> ClipboardStoredItem? {
    try? historyStore.selectedItem(id: id)
  }

  func setPinned(_ isPinned: Bool, itemID: String) {
    try? historyStore.setPinned(isPinned, itemID: itemID)
  }

  func delete(itemID: String) {
    try? historyStore.delete(itemID: itemID)
  }

  @discardableResult
  func export(day: Date) throws -> DailyExportResult {
    try dailyExporter().export(day: day)
  }

  func exportRecord(day: Date) -> DailyExportRecord? {
    try? database.exportRecord(day: day)
  }

  func exportItemCount(day: Date, calendar: Calendar = .current) -> Int? {
    let start = calendar.startOfDay(for: day)
    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
      return nil
    }
    return try? database.itemCount(from: start, to: end)
  }

  @discardableResult
  func removeOrphanAssets() -> [String] {
    (try? dailyExporter().removeOrphanAssets()) ?? []
  }

  @discardableResult
  func generatePendingThumbnails(limit: Int = 20) -> Int {
    let jobs = (try? database.pendingThumbnailJobs(limit: limit)) ?? []
    var generated = 0

    for job in jobs {
      guard let originalData = try? assetStore.read(job.assetPath),
            let thumbnailData = ImageThumbnailGenerator.pngThumbnail(from: originalData, maxPixelSize: 512),
            let thumbnailAsset = try? assetStore.write(thumbnailData, type: ClipboardContentType.png) else {
        continue
      }

      do {
        try database.markThumbnailGenerated(
          contentHash: job.contentHash,
          thumbnailPath: thumbnailAsset.relativePath
        )
        generated += 1
      } catch {
        try? assetStore.remove(thumbnailAsset.relativePath)
      }
    }

    return generated
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
