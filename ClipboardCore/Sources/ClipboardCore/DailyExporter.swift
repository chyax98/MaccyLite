import Foundation

public struct DailyExportResult: Sendable, Equatable {
  public var day: Date
  public var url: URL
  public var itemCount: Int

  public init(day: Date, url: URL, itemCount: Int) {
    self.day = day
    self.url = url
    self.itemCount = itemCount
  }
}

public struct AssetHealthReport: Sendable, Equatable {
  public var referencedCount: Int
  public var existingCount: Int
  public var missing: [String]
  public var orphaned: [String]

  public var isHealthy: Bool {
    missing.isEmpty
  }

  public init(referencedCount: Int, existingCount: Int, missing: [String], orphaned: [String]) {
    self.referencedCount = referencedCount
    self.existingCount = existingCount
    self.missing = missing
    self.orphaned = orphaned
  }
}

public final class DailyExporter: @unchecked Sendable {
  private let batchSize = 250
  private let orphanCleanupMinimumAge: TimeInterval
  private let database: ClipboardDatabase
  private let assetStore: AssetStore
  private let exportDirectory: URL
  private let calendar: Calendar

  public init(
    database: ClipboardDatabase,
    assetStore: AssetStore,
    exportDirectory: URL,
    calendar: Calendar = .current,
    orphanCleanupMinimumAge: TimeInterval = 300
  ) {
    self.database = database
    self.assetStore = assetStore
    self.exportDirectory = exportDirectory
    self.calendar = calendar
    self.orphanCleanupMinimumAge = orphanCleanupMinimumAge
  }

  public func export(day: Date) throws -> DailyExportResult {
    let start = calendar.startOfDay(for: day)
    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
      throw CocoaError(.featureUnsupported)
    }

    let itemCount = try database.itemCount(from: start, to: end)
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

    let filename = "\(Self.dayKey(start)).md"
    let url = exportDirectory.appending(path: filename)
    let temporaryURL = exportDirectory.appending(path: ".\(filename).tmp-\(UUID().uuidString)")
    _ = FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: temporaryURL)
    var temporaryFileNeedsCleanup = true
    var handleNeedsClose = true
    defer {
      if handleNeedsClose {
        try? handle.close()
      }
      if temporaryFileNeedsCleanup {
        try? FileManager.default.removeItem(at: temporaryURL)
      }
    }

    try writeMarkdown(day: start, itemCount: itemCount, from: start, to: end, to: handle)
    try handle.close()
    handleNeedsClose = false
    try replaceExportFile(at: url, with: temporaryURL)
    temporaryFileNeedsCleanup = false
    try database.recordExport(day: start, path: url.path, itemCount: itemCount)

    return DailyExportResult(day: start, url: url, itemCount: itemCount)
  }

  public func removeOrphanAssets() throws -> [String] {
    let orphaned = try orphanAssetPaths()

    for path in orphaned {
      try assetStore.remove(path)
    }

    return orphaned
  }

  public func orphanAssetPaths() throws -> [String] {
    let referenced = try database.referencedAssetPaths()
    let existing = try assetStore.allRelativePaths(olderThan: orphanCleanupMinimumAge)
    return existing.subtracting(referenced).sorted()
  }

  public func assetHealthReport() throws -> AssetHealthReport {
    let referenced = try database.referencedAssetPaths()
    let existing = try assetStore.allRelativePaths()
    return AssetHealthReport(
      referencedCount: referenced.count,
      existingCount: existing.count,
      missing: referenced.subtracting(existing).sorted(),
      orphaned: existing.subtracting(referenced).sorted()
    )
  }

  private func writeMarkdown(
    day: Date,
    itemCount: Int,
    from start: Date,
    to end: Date,
    to handle: FileHandle
  ) throws {
    try writeLines([
      "# 剪贴板导出 \(Self.dayKey(day))",
      "",
      "- 条目数：\(itemCount)",
      ""
    ], to: handle)

    var cursorCopiedAt: Date?
    var cursorID: String?
    while true {
      let items = try database.items(
        from: start,
        to: end,
        afterCopiedAt: cursorCopiedAt,
        afterID: cursorID,
        limit: batchSize
      )
      guard !items.isEmpty else {
        break
      }

      for item in items {
        try write(item: item, to: handle)
      }

      cursorCopiedAt = items.last?.copiedAt
      cursorID = items.last?.id
    }
  }

  private func write(item: ClipboardStoredItem, to handle: FileHandle) throws {
    var lines = [
      "## \(Self.timeFormatter.string(from: item.copiedAt))",
      "",
      "- 来源：\(item.sourceApp ?? "未知")",
      "- 类型：\(item.primaryType)",
      "- 次数：\(item.copyCount)",
      ""
    ]

    if !item.displayText.isEmpty {
      lines.append(markdownCodeBlock(item.displayText))
      lines.append("")
    }

    if !item.contents.isEmpty {
      lines.append("内容：")
      for content in item.contents {
        lines.append("- 类型：\(content.pasteboardType)")
        lines.append("  - 字节：\(content.byteCount)")

        if content.pasteboardType == ClipboardContentType.fileURL,
           let data = content.inlineData,
           let fileURL = String(data: data, encoding: .utf8) {
          lines.append("  - 文件 URL：\(fileURL)")
        }

        if let imageWidth = content.imageWidth, let imageHeight = content.imageHeight {
          lines.append("  - 图片尺寸：\(imageWidth)x\(imageHeight)")
        }

        if let assetPath = content.assetPath {
          lines.append("  - 资产：`\(assetPath)`")
        }

        if content.pasteboardType == ClipboardContentType.plainText,
           let text = try fullText(for: content),
           text != item.displayText {
          lines.append("")
          lines.append("完整文本：")
          lines.append(markdownCodeBlock(text))
        }
      }
      lines.append("")
    }

    try writeLines(lines, to: handle)
  }

  private func writeLines(_ lines: [String], to handle: FileHandle) throws {
    guard let data = lines.joined(separator: "\n").appending("\n").data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    try handle.write(contentsOf: data)
  }

  private func markdownCodeBlock(_ text: String) -> String {
    let longestFence = text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
      .map { line in line.prefix { $0 == "`" }.count }
      .max() ?? 2
    let fence = String(repeating: "`", count: max(3, longestFence + 1))
    return "\(fence)text\n\(text)\n\(fence)"
  }

  private func fullText(for content: ClipboardStoredContent) throws -> String? {
    let data: Data?
    if let assetPath = content.assetPath {
      data = try assetStore.read(assetPath)
    } else if let inlineData = content.inlineData {
      data = inlineData
    } else {
      data = nil
    }

    guard let data else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  private func replaceExportFile(at destination: URL, with temporaryURL: URL) throws {
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
    } else {
      try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
  }

  private static func dayKey(_ date: Date) -> String {
    dayFormatter.string(from: date)
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}
