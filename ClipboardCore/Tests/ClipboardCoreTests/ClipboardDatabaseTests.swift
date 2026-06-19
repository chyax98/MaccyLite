import Foundation
import Testing
@testable import ClipboardCore

@Test
func databaseInsertsListsAndSearchesClipboardItems() throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    sourceApp: "com.apple.TextEdit",
    primaryType: "public.utf8-plain-text",
    displayText: "今天要整理数据库方案",
    searchText: "今天要整理数据库方案 https://example.com/key",
    contents: [
      ClipboardContentDraft(
        pasteboardType: "public.utf8-plain-text",
        byteCount: 36,
        inlineData: Data("今天要整理数据库方案".utf8),
        assetPath: nil,
        contentHash: "hash-1"
      )
    ]
  ))

  #expect(try database.latest().map(\.displayText) == ["今天要整理数据库方案"])
  #expect(try database.search("数据库").map(\.displayText) == ["今天要整理数据库方案"])
  #expect(try database.search("example").map(\.displayText) == ["今天要整理数据库方案"])
}

@Test
func databaseMergesDuplicateClipboardItems() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let data = Data("重复复制内容".utf8)
  let first = try database.insert(ClipboardItemDraft(
    id: "first-copy",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: "first.app",
    primaryType: ClipboardContentType.plainText,
    displayText: "重复复制内容",
    searchText: "重复复制内容",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: data.count,
        inlineData: data,
        assetPath: nil,
        contentHash: AssetStore.sha256(data)
      )
    ]
  ))

  let second = try database.insert(ClipboardItemDraft(
    id: "second-copy",
    copiedAt: Date(timeIntervalSince1970: 2),
    sourceApp: "second.app",
    primaryType: ClipboardContentType.plainText,
    displayText: "重复复制内容",
    searchText: "重复复制内容",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: data.count,
        inlineData: data,
        assetPath: nil,
        contentHash: AssetStore.sha256(data)
      )
    ]
  ))

  #expect(second.id == first.id)
  #expect(try database.latest().map(\.id) == [first.id])
  let listItem = try #require(try database.latest().first)
  #expect(listItem.copyCount == 2)
  #expect(listItem.copiedAt == Date(timeIntervalSince1970: 2))

  let stored = try #require(try database.item(id: first.id))
  #expect(stored.sourceApp == "second.app")
  #expect(stored.contents.count == 1)
}

@Test
func databaseFindsShortChineseQueryOutsideRecentSearchScope() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "old-target",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "健康计划",
    searchText: "健康计划",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 12,
        inlineData: Data("健康计划".utf8),
        assetPath: nil,
        contentHash: "old-target"
      )
    ]
  ))

  for index in 0..<5_001 {
    try database.insert(ClipboardItemDraft(
      id: "recent-\(index)",
      copiedAt: Date(timeIntervalSince1970: Double(index + 2)),
      sourceApp: nil,
      primaryType: ClipboardContentType.plainText,
      displayText: "普通记录 \(index)",
      searchText: "普通记录 \(index)",
      contents: [
        ClipboardContentDraft(
          pasteboardType: ClipboardContentType.plainText,
          byteCount: 16,
          inlineData: Data("普通记录 \(index)".utf8),
          assetPath: nil,
          contentHash: "recent-\(index)"
        )
      ]
    ))
  }

  #expect(try database.search("健康", limit: 10).map(\.id) == ["old-target"])
}

@Test
func databaseSearchMatchesMultipleTermsWithoutRequiringExactPhrase() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "multi-term",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "SQLite export notes",
    searchText: "SQLite daily markdown export notes",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 34,
        inlineData: Data("SQLite daily markdown export notes".utf8),
        assetPath: nil,
        contentHash: "multi-term"
      )
    ]
  ))
  try database.insert(ClipboardItemDraft(
    id: "phrase-only",
    copiedAt: Date(timeIntervalSince1970: 2),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "export sqlite",
    searchText: "export sqlite",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 13,
        inlineData: Data("export sqlite".utf8),
        assetPath: nil,
        contentHash: "phrase-only"
      )
    ]
  ))

  #expect(Set(try database.search("SQLite export", limit: 10).map(\.id)) == ["multi-term", "phrase-only"])
}

@Test
func databaseSearchRanksExactAndPrefixMatchesBeforeRecentContainsMatches() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "exact",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "token",
    searchText: "token",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 5,
        inlineData: Data("token".utf8),
        assetPath: nil,
        contentHash: "exact"
      )
    ]
  ))
  try database.insert(ClipboardItemDraft(
    id: "prefix",
    copiedAt: Date(timeIntervalSince1970: 2),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "token prefix",
    searchText: "token prefix",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 12,
        inlineData: Data("token prefix".utf8),
        assetPath: nil,
        contentHash: "prefix"
      )
    ]
  ))
  try database.insert(ClipboardItemDraft(
    id: "recent-contains",
    copiedAt: Date(timeIntervalSince1970: 3),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "newer contains token",
    searchText: "newer contains token",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 20,
        inlineData: Data("newer contains token".utf8),
        assetPath: nil,
        contentHash: "recent-contains"
      )
    ]
  ))

  #expect(try database.search("token", limit: 10).map(\.id) == ["exact", "prefix", "recent-contains"])
}

@Test
func databaseSearchMatchesURLFilenameTokensSplitByPunctuation() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let url = "file:///Users/xd/Desktop/daily-report.md"

  try database.insert(ClipboardItemDraft(
    id: "file-url",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: "com.apple.finder",
    primaryType: ClipboardContentType.fileURL,
    displayText: url,
    searchText: url,
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.fileURL,
        byteCount: Data(url.utf8).count,
        inlineData: Data(url.utf8),
        assetPath: nil,
        contentHash: "file-url"
      )
    ]
  ))

  #expect(try database.search("report md", limit: 10).map(\.id) == ["file-url"])
  #expect(try database.search("repo md", limit: 10).map(\.id) == ["file-url"])
}

@Test
func storagePolicyStoresLargeTextAsAssetAndKeepsPrefixInline() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let policy = StoragePolicy(textInlineLimit: 16, previewLimit: 12)
  let data = Data("这是一段明显超过阈值的中文长文本".utf8)

  let draft = try policy.contentDraft(
    type: ClipboardContentType.plainText,
    data: data,
    assetStore: assetStore
  )

  #expect(draft.assetPath != nil)
  #expect(draft.inlineData != nil)
  #expect(draft.inlineData!.count <= 12)
  #expect(try assetStore.read(draft.assetPath!) == data)
}

@Test
func dailyExporterWritesMarkdownAndRemovesOrphanAssets() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let copiedAt = Date(timeIntervalSince1970: 1_719_187_200) // 2024-06-23 00:00:00 UTC
  let fullText = "  长期保存的大文本内容，应该完整进入每日 Markdown 导出，不能只留下资产路径。\n```swift\nlet value = 1\n```\n\n"
  let data = Data(fullText.utf8)
  let asset = try assetStore.write(data, type: ClipboardContentType.plainText, copiedAt: copiedAt)
  let orphan = try assetStore.write(Data("孤儿文件".utf8), type: ClipboardContentType.plainText, copiedAt: copiedAt)

  try database.insert(ClipboardItemDraft(
    copiedAt: copiedAt,
    sourceApp: "com.apple.TextEdit",
    primaryType: ClipboardContentType.plainText,
    displayText: "长期保存",
    searchText: fullText,
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: data.count,
        inlineData: Data("长期保存".utf8),
        assetPath: asset.relativePath,
        contentHash: asset.hash
      )
    ]
  ))

  let exporter = DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: directory.appending(path: "Exports"),
    calendar: Calendar(identifier: .gregorian),
    orphanCleanupMinimumAge: 0
  )

  let result = try exporter.export(day: copiedAt)
  let markdown = try String(contentsOf: result.url, encoding: .utf8)

  #expect(result.itemCount == 1)
  #expect(markdown.contains("剪贴板导出"))
  #expect(markdown.contains("完整文本"))
  #expect(markdown.contains(fullText))
  #expect(markdown.contains("````text"))
  #expect(markdown.contains(asset.relativePath))
  #expect(try database.exportRecord(day: copiedAt)?.itemCount == 1)

  try "stale export".write(to: result.url, atomically: true, encoding: .utf8)
  let rewritten = try exporter.export(day: copiedAt)
  let rewrittenMarkdown = try String(contentsOf: rewritten.url, encoding: .utf8)
  let exportFiles = try FileManager.default.contentsOfDirectory(
    at: directory.appending(path: "Exports"),
    includingPropertiesForKeys: nil
  )
  #expect(rewrittenMarkdown.contains(fullText))
  #expect(!rewrittenMarkdown.contains("stale export"))
  #expect(!exportFiles.contains { $0.lastPathComponent.contains(".tmp-") })

  let orphanPaths = try exporter.orphanAssetPaths()
  #expect(orphanPaths == [orphan.relativePath])
  #expect(assetStore.exists(orphan.relativePath))

  let removed = try exporter.removeOrphanAssets()
  #expect(removed == [orphan.relativePath])
  #expect(assetStore.exists(asset.relativePath))
  #expect(!assetStore.exists(orphan.relativePath))
}

@Test
func dailyExporterReportsMissingAndOrphanAssets() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let copiedAt = Date(timeIntervalSince1970: 1_719_187_200)
  let missingPath = "2024/06/23/missing.txt"
  let orphan = try assetStore.write(Data("孤儿文件".utf8), type: ClipboardContentType.plainText, copiedAt: copiedAt)

  try database.insert(ClipboardItemDraft(
    copiedAt: copiedAt,
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "缺失资产",
    searchText: "缺失资产",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: 12,
        inlineData: nil,
        assetPath: missingPath,
        contentHash: "missing"
      )
    ]
  ))

  let report = try DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: directory.appending(path: "Exports"),
    calendar: Calendar(identifier: .gregorian)
  ).assetHealthReport()

  #expect(!report.isHealthy)
  #expect(report.referencedCount == 1)
  #expect(report.existingCount == 1)
  #expect(report.missing == [missingPath])
  #expect(report.orphaned == [orphan.relativePath])
}

@Test
func orphanCleanupSkipsFreshAssetsByDefault() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let orphan = try assetStore.write(Data("刚写入，还可能等待入库".utf8), type: ClipboardContentType.plainText)

  let exporter = DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: directory.appending(path: "Exports")
  )

  #expect(try exporter.orphanAssetPaths().isEmpty)
  #expect(assetStore.exists(orphan.relativePath))
}

@Test
func dailyExporterWritesFileURLsAndImageMetadata() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let copiedAt = Date(timeIntervalSince1970: 1_719_273_600) // 2024-06-24 00:00:00 UTC
  let imageData = try onePixelPNG()
  let imageAsset = try assetStore.write(imageData, type: ClipboardContentType.png, copiedAt: copiedAt)
  let fileURL = "file:///Users/xd/Desktop/report.md"
  let fileURLData = Data(fileURL.utf8)

  try database.insert(ClipboardItemDraft(
    copiedAt: copiedAt,
    sourceApp: "com.apple.finder",
    primaryType: ClipboardContentType.fileURL,
    displayText: fileURL,
    searchText: fileURL,
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.fileURL,
        byteCount: fileURLData.count,
        inlineData: fileURLData,
        assetPath: nil,
        contentHash: AssetStore.sha256(fileURLData)
      ),
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.png,
        byteCount: imageData.count,
        inlineData: nil,
        assetPath: imageAsset.relativePath,
        contentHash: imageAsset.hash,
        imageWidth: 1,
        imageHeight: 1
      )
    ]
  ))

  let exporter = DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: directory.appending(path: "Exports"),
    calendar: Calendar(identifier: .gregorian)
  )

  let result = try exporter.export(day: copiedAt)
  let markdown = try String(contentsOf: result.url, encoding: .utf8)

  #expect(markdown.contains("- 类型：\(ClipboardContentType.fileURL)"))
  #expect(markdown.contains("- 文件 URL：\(fileURL)"))
  #expect(markdown.contains("- 类型：\(ClipboardContentType.png)"))
  #expect(markdown.contains("- 图片尺寸：1x1"))
  #expect(markdown.contains(imageAsset.relativePath))
}

@Test
func databasePinsAndDeletesItems() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "older",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "旧项目",
    searchText: "旧项目",
    contents: []
  ))
  try database.insert(ClipboardItemDraft(
    id: "newer",
    copiedAt: Date(timeIntervalSince1970: 2),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "新项目",
    searchText: "新项目",
    contents: []
  ))

  #expect(try database.latest().map(\.id) == ["newer", "older"])

  try database.setPinned(true, itemID: "older")
  #expect(try database.latest().map(\.id) == ["older", "newer"])

  try database.delete(itemID: "older")
  #expect(try database.latest().map(\.id) == ["newer"])
  #expect(try database.search("旧项目").isEmpty)
}

@Test
func databaseDeletesUnpinnedItemsInBatchAndKeepsPinnedItems() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "pinned",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "保留",
    searchText: "保留",
    contents: []
  ))
  try database.insert(ClipboardItemDraft(
    id: "unpinned",
    copiedAt: Date(timeIntervalSince1970: 2),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "删除",
    searchText: "删除",
    contents: []
  ))

  try database.setPinned(true, itemID: "pinned")
  try database.deleteUnpinned()

  #expect(try database.latest().map(\.id) == ["pinned"])
  #expect(try database.search("删除").isEmpty)
}

@Test
func databaseDeletesAllItemsInBatch() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "first",
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "第一条",
    searchText: "第一条",
    contents: []
  ))
  try database.insert(ClipboardItemDraft(
    id: "second",
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "第二条",
    searchText: "第二条",
    contents: []
  ))

  try database.deleteAll()

  #expect(try database.latest().isEmpty)
  #expect(try database.search("第一条").isEmpty)
}

@Test
func databaseReturnsLatestUnpinnedDisplayTextForMenuBar() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))

  try database.insert(ClipboardItemDraft(
    id: "old",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "旧文本",
    searchText: "旧文本",
    contents: []
  ))
  try database.insert(ClipboardItemDraft(
    id: "new",
    copiedAt: Date(timeIntervalSince1970: 2),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "新文本",
    searchText: "新文本",
    contents: []
  ))

  #expect(try database.latestUnpinnedDisplayText() == "新文本")

  try database.setPinned(true, itemID: "new")
  #expect(try database.latestUnpinnedDisplayText() == "旧文本")
}

@Test
func databaseReturnsStoredItemsWithContents() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let textData = Data("完整内容".utf8)

  try database.insert(ClipboardItemDraft(
    id: "stored",
    sourceApp: "com.apple.TextEdit",
    primaryType: ClipboardContentType.plainText,
    displayText: "完整内容",
    searchText: "完整内容 searchable-token",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: textData.count,
        inlineData: textData,
        assetPath: nil,
        contentHash: AssetStore.sha256(textData)
      )
    ]
  ))

  #expect(try database.latestStored().first?.contents.first?.inlineData == textData)
  #expect(try database.searchStored("searchable-token").first?.id == "stored")
  #expect(try database.item(id: "stored")?.contents.first?.pasteboardType == ClipboardContentType.plainText)
}

@Test
func databaseListItemsExposeOnlyListMetadata() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let imageData = try onePixelPNG()
  let imageAsset = try assetStore.write(imageData, type: ClipboardContentType.png)

  try database.insert(ClipboardItemDraft(
    id: "image-list-item",
    sourceApp: "com.apple.screencapture",
    primaryType: ClipboardContentType.png,
    displayText: "图片",
    searchText: "",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.png,
        byteCount: imageData.count,
        inlineData: nil,
        assetPath: imageAsset.relativePath,
        contentHash: imageAsset.hash,
        imageWidth: 1,
        imageHeight: 1
      )
    ]
  ))

  let listItem = try #require(database.latest().first)
  #expect(listItem.id == "image-list-item")
  #expect(listItem.copyCount == 1)
  #expect(listItem.hasImage)

  let storedItem = try #require(try database.item(id: listItem.id))
  #expect(storedItem.contents.first?.assetPath == imageAsset.relativePath)
}

@Test
func pasteboardPayloadResolverRestoresInlineAndAssetPayloads() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let asset = try assetStore.write(Data("<b>完整 HTML</b>".utf8), type: ClipboardContentType.html)
  let textData = Data("纯文本".utf8)
  let item = ClipboardStoredItem(
    id: "payload",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "纯文本",
    searchText: "纯文本",
    isPinned: false,
    copyCount: 1,
    contents: [
      ClipboardStoredContent(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: textData.count,
        inlineData: textData,
        assetPath: nil,
        contentHash: AssetStore.sha256(textData)
      ),
      ClipboardStoredContent(
        pasteboardType: ClipboardContentType.html,
        byteCount: 18,
        inlineData: nil,
        assetPath: asset.relativePath,
        contentHash: asset.hash
      )
    ]
  )
  let resolver = ClipboardPasteboardPayloadResolver { path in
    try assetStore.read(path)
  }

  let payloads = try resolver.payloads(for: item)

  #expect(payloads == [
    ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.plainText, data: textData),
    ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.html, data: Data("<b>完整 HTML</b>".utf8))
  ])
}

@Test
func pasteboardPayloadResolverRemoveFormattingKeepsPlainTextAndFileURLs() throws {
  let textData = Data("纯文本".utf8)
  let htmlData = Data("<b>纯文本</b>".utf8)
  let fileURLData = Data("file:///Users/xd/Desktop/a.txt".utf8)
  let item = ClipboardStoredItem(
    id: "remove-formatting",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.html,
    displayText: "纯文本",
    searchText: "纯文本",
    isPinned: false,
    copyCount: 1,
    contents: [
      ClipboardStoredContent(
        pasteboardType: ClipboardContentType.html,
        byteCount: htmlData.count,
        inlineData: htmlData,
        assetPath: nil,
        contentHash: AssetStore.sha256(htmlData)
      ),
      ClipboardStoredContent(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: textData.count,
        inlineData: textData,
        assetPath: nil,
        contentHash: AssetStore.sha256(textData)
      ),
      ClipboardStoredContent(
        pasteboardType: ClipboardContentType.fileURL,
        byteCount: fileURLData.count,
        inlineData: fileURLData,
        assetPath: nil,
        contentHash: AssetStore.sha256(fileURLData)
      )
    ]
  )
  let resolver = ClipboardPasteboardPayloadResolver { _ in
    throw ClipboardPasteboardPayloadError.missingAsset("unexpected")
  }

  let payloads = try resolver.payloads(for: item, removeFormatting: true)

  #expect(payloads == [
    ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.plainText, data: textData),
    ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.fileURL, data: fileURLData)
  ])
}

@Test
func pasteboardPayloadResolverReportsMissingAssetPayloads() throws {
  let item = ClipboardStoredItem(
    id: "missing-asset",
    copiedAt: Date(timeIntervalSince1970: 1),
    sourceApp: nil,
    primaryType: ClipboardContentType.html,
    displayText: "HTML",
    searchText: "HTML",
    isPinned: false,
    copyCount: 1,
    contents: [
      ClipboardStoredContent(
        pasteboardType: ClipboardContentType.html,
        byteCount: 10,
        inlineData: nil,
        assetPath: nil,
        contentHash: "hash"
      )
    ]
  )
  let resolver = ClipboardPasteboardPayloadResolver { _ in Data() }

  #expect(throws: ClipboardPasteboardPayloadError.missingAsset(ClipboardContentType.html)) {
    try resolver.payloads(for: item)
  }
}

@Test
func dailyExportSchedulePolicyComputesTodayFireDateWhenTimeIsStillAhead() throws {
  let calendar = utcCalendar()
  let policy = DailyExportSchedulePolicy(hour: 23, minute: 30, catchUpDays: 7, calendar: calendar)
  let now = try date("2026-06-19T12:00:00Z", calendar: calendar)
  let expected = try date("2026-06-19T23:30:00Z", calendar: calendar)

  #expect(policy.nextFireDate(after: now) == expected)
}

@Test
func dailyExportSchedulePolicyComputesTomorrowFireDateWhenTimePassed() throws {
  let calendar = utcCalendar()
  let policy = DailyExportSchedulePolicy(hour: 0, minute: 5, catchUpDays: 7, calendar: calendar)
  let now = try date("2026-06-19T12:00:00Z", calendar: calendar)
  let expected = try date("2026-06-20T00:05:00Z", calendar: calendar)

  #expect(policy.nextFireDate(after: now) == expected)
}

@Test
func dailyExportSchedulePolicyClampsConfigAndCatchUpDays() throws {
  let calendar = utcCalendar()
  let policy = DailyExportSchedulePolicy(hour: 99, minute: -1, catchUpDays: 99, calendar: calendar)
  let now = try date("2026-06-19T23:30:00Z", calendar: calendar)
  let expectedNextFireDate = try date("2026-06-20T23:00:00Z", calendar: calendar)
  let expectedFirstCatchUpDay = try date("2026-06-18T23:30:00Z", calendar: calendar)

  #expect(policy.hour == 23)
  #expect(policy.minute == 0)
  #expect(policy.catchUpDays == 30)
  #expect(policy.nextFireDate(after: now) == expectedNextFireDate)
  #expect(policy.catchUpExportDays(before: now).count == 30)
  #expect(policy.catchUpExportDays(before: now).first == expectedFirstCatchUpDay)
}

@Test
func dailyExportSchedulePolicyDetectsCurrentAndStaleExports() throws {
  let calendar = utcCalendar()
  let policy = DailyExportSchedulePolicy(hour: 0, minute: 5, catchUpDays: 3, calendar: calendar)
  let record = DailyExportRecord(
    day: "2026-06-18",
    path: "/tmp/2026-06-18.md",
    itemCount: 12,
    exportedAt: try date("2026-06-19T00:05:00Z", calendar: calendar)
  )

  #expect(policy.exportIsCurrent(record: record, fileExists: true, currentItemCount: 12))
  #expect(!policy.exportIsCurrent(record: nil, fileExists: true, currentItemCount: 12))
  #expect(!policy.exportIsCurrent(record: record, fileExists: false, currentItemCount: 12))
  #expect(!policy.exportIsCurrent(record: record, fileExists: true, currentItemCount: nil))
  #expect(!policy.exportIsCurrent(record: record, fileExists: true, currentItemCount: 13))
}

@Test
func dailyExportSchedulePolicyFiltersCatchUpDaysToMissingExports() throws {
  let calendar = utcCalendar()
  let policy = DailyExportSchedulePolicy(hour: 0, minute: 5, catchUpDays: 3, calendar: calendar)
  let now = try date("2026-06-19T12:00:00Z", calendar: calendar)
  let currentDay = try date("2026-06-18T12:00:00Z", calendar: calendar)

  let missing = policy.missingExportDays(before: now) { day in
    calendar.isDate(day, inSameDayAs: currentDay)
  }

  #expect(missing.map { calendar.component(.day, from: $0) } == [17, 16])
}

@Test
func clipboardHistoryStoreCoversLoadSearchSelectDeleteAndPinBoundary() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let store = ClipboardHistoryStore(
    database: database,
    capture: ClipboardCapture(assetStore: assetStore)
  )

  let first = try #require(try store.insert(
    contents: [
      ClipboardRawContent(
        pasteboardType: ClipboardContentType.plainText,
        data: Data("第一条 数据库".utf8)
      )
    ],
    sourceApp: "tests",
    copiedAt: Date(timeIntervalSince1970: 1)
  ))
  let second = try #require(try store.insert(
    contents: [
      ClipboardRawContent(
        pasteboardType: ClipboardContentType.plainText,
        data: Data("第二条 example".utf8)
      )
    ],
    sourceApp: "tests",
    copiedAt: Date(timeIntervalSince1970: 2)
  ))

  #expect(try store.latest().map(\.id) == [second.id, first.id])
  #expect(try store.search("数据库").map(\.id) == [first.id])
  #expect(try store.selectedItem(id: second.id)?.displayText == "第二条 example")

  try store.setPinned(true, itemID: first.id)
  #expect(try store.latest().map(\.id) == [first.id, second.id])

  try store.delete(itemID: first.id)
  #expect(try store.latest().map(\.id) == [second.id])
  #expect(try store.selectedItem(id: first.id) == nil)
}

@Test
func clipboardHistoryStoreLargeObjectSearchExportAndPayloadRoundTrip() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let policy = StoragePolicy(
    textInlineLimit: 32,
    richTextInlineLimit: 32,
    genericInlineLimit: 32,
    previewLimit: 18,
    displayCharacterLimit: 24,
    searchTextLimit: 2_000
  )
  let store = ClipboardHistoryStore(
    database: database,
    capture: ClipboardCapture(policy: policy, assetStore: assetStore)
  )
  let copiedAt = Date(timeIntervalSince1970: 1_719_360_000) // 2024-06-25 00:00:00 UTC
  let longText = String(repeating: "大对象复制性能测试 ", count: 30) + "terminal-token"
  let textData = Data(longText.utf8)
  let fileURL = "file:///Users/xd/Desktop/daily-signal/report.md"
  let imageData = try onePixelPNG()
  let orphan = try assetStore.write(Data("可清理孤儿资产".utf8), type: ClipboardContentType.plainText, copiedAt: copiedAt)

  let inserted = try #require(try store.insert(
    contents: [
      ClipboardRawContent(pasteboardType: ClipboardContentType.plainText, data: textData),
      ClipboardRawContent(pasteboardType: ClipboardContentType.fileURL, data: Data(fileURL.utf8)),
      ClipboardRawContent(pasteboardType: ClipboardContentType.png, data: imageData)
    ],
    sourceApp: "tests.large-object",
    copiedAt: copiedAt
  ))

  let listItem = try #require(try store.latestList().first)
  #expect(listItem.id == inserted.id)
  #expect(listItem.hasImage)
  #expect(listItem.displayText.count <= policy.displayCharacterLimit)

  #expect(try store.search("terminal-token").map(\.id) == [inserted.id])
  #expect(try store.search("daily signal report md").map(\.id) == [inserted.id])

  let stored = try #require(try store.selectedItem(id: inserted.id))
  let textContent = try #require(stored.contents.first { $0.pasteboardType == ClipboardContentType.plainText })
  let imageContent = try #require(stored.contents.first { $0.pasteboardType == ClipboardContentType.png })
  #expect(textContent.assetPath != nil)
  #expect(textContent.inlineData?.count ?? 0 <= policy.previewLimit)
  #expect(try assetStore.read(textContent.assetPath!) == textData)
  #expect(imageContent.assetPath != nil)
  #expect(imageContent.imageWidth == 1)
  #expect(imageContent.imageHeight == 1)

  let resolver = ClipboardPasteboardPayloadResolver { path in
    try assetStore.read(path)
  }
  let payloads = try resolver.payloads(for: stored)
  #expect(payloads.contains(ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.plainText, data: textData)))
  #expect(payloads.contains(ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.fileURL, data: Data(fileURL.utf8))))
  #expect(payloads.contains(ClipboardPasteboardPayload(pasteboardType: ClipboardContentType.png, data: imageData)))

  let exporter = DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: directory.appending(path: "Exports"),
    calendar: Calendar(identifier: .gregorian),
    orphanCleanupMinimumAge: 0
  )
  let result = try exporter.export(day: copiedAt)
  let markdown = try String(contentsOf: result.url, encoding: .utf8)

  #expect(result.itemCount == 1)
  #expect(markdown.contains(longText))
  #expect(markdown.contains(fileURL))
  #expect(markdown.contains("- 图片尺寸：1x1"))
  #expect(markdown.contains(textContent.assetPath!))
  #expect(markdown.contains(imageContent.assetPath!))

  #expect(try exporter.removeOrphanAssets() == [orphan.relativePath])
  #expect(assetStore.exists(textContent.assetPath!))
  #expect(assetStore.exists(imageContent.assetPath!))
  #expect(!assetStore.exists(orphan.relativePath))
}

@Test
func clipboardHistoryStoreTrimsOnlyUnpinnedItems() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let store = ClipboardHistoryStore(
    database: database,
    capture: ClipboardCapture(assetStore: assetStore)
  )

  let oldest = try #require(try store.insert(
    contents: [ClipboardRawContent(pasteboardType: ClipboardContentType.plainText, data: Data("oldest".utf8))],
    sourceApp: nil,
    copiedAt: Date(timeIntervalSince1970: 1)
  ))
  let middle = try #require(try store.insert(
    contents: [ClipboardRawContent(pasteboardType: ClipboardContentType.plainText, data: Data("middle".utf8))],
    sourceApp: nil,
    copiedAt: Date(timeIntervalSince1970: 2)
  ))
  let newest = try #require(try store.insert(
    contents: [ClipboardRawContent(pasteboardType: ClipboardContentType.plainText, data: Data("newest".utf8))],
    sourceApp: nil,
    copiedAt: Date(timeIntervalSince1970: 3)
  ))

  try store.setPinned(true, itemID: oldest.id)
  try store.trimUnpinned(maxCount: 1)

  #expect(try store.latest().map(\.id) == [oldest.id, newest.id])
  #expect(try store.selectedItem(id: middle.id) == nil)
}

@Test
func databaseHealthReportAndReindexCoverSearchIndexes() throws {
  let directory = try temporaryDirectory()
  let database = try ClipboardDatabase(path: directory.appending(path: "Clipboard.sqlite"))
  let firstData = Data("数据库健康检查".utf8)
  let secondData = Data("example reindex token".utf8)

  try database.insert(ClipboardItemDraft(
    id: "health-1",
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "数据库健康检查",
    searchText: "数据库健康检查",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: firstData.count,
        inlineData: firstData,
        assetPath: nil,
        contentHash: AssetStore.sha256(firstData)
      )
    ]
  ))
  try database.insert(ClipboardItemDraft(
    id: "health-2",
    sourceApp: nil,
    primaryType: ClipboardContentType.plainText,
    displayText: "example reindex token",
    searchText: "example reindex token",
    contents: [
      ClipboardContentDraft(
        pasteboardType: ClipboardContentType.plainText,
        byteCount: secondData.count,
        inlineData: secondData,
        assetPath: nil,
        contentHash: AssetStore.sha256(secondData)
      )
    ]
  ))

  var report = try database.healthReport()
  #expect(report.isHealthy)
  #expect(report.itemCount == 2)
  #expect(report.contentCount == 2)
  #expect(report.searchIndexCount == 2)
  #expect(report.trigramIndexCount == 2)
  #expect(report.missingSearchIndexCount == 0)
  #expect(report.missingTrigramIndexCount == 0)

  try database.rebuildSearchIndexes()

  report = try database.healthReport()
  #expect(report.isHealthy)
  #expect(report.searchIndexCount == 2)
  #expect(report.trigramIndexCount == 2)
  #expect(try database.search("健康").map(\.id) == ["health-1"])
  #expect(try database.search("reindex").map(\.id) == ["health-2"])
}

@Test
func captureBuildsItemFromMultiplePasteboardTypes() throws {
  let directory = try temporaryDirectory()
  let capture = ClipboardCapture(assetStore: AssetStore(root: directory.appending(path: "Assets")))

  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(
        pasteboardType: ClipboardContentType.html,
        data: Data("<p>数据库 <strong>方案</strong></p>".utf8)
      ),
      ClipboardRawContent(
        pasteboardType: ClipboardContentType.plainText,
        data: Data("数据库方案".utf8)
      )
    ],
    sourceApp: "com.apple.Safari",
    copiedAt: Date(timeIntervalSince1970: 10)
  )
  let item = try #require(captured)

  #expect(item.sourceApp == "com.apple.Safari")
  #expect(item.primaryType == ClipboardContentType.plainText)
  #expect(item.displayText == "数据库方案")
  #expect(item.searchText.contains("数据库方案"))
  #expect(item.contents.map(\.pasteboardType) == [
    ClipboardContentType.plainText,
    ClipboardContentType.html
  ])
}

@Test
func captureExtractsHTMLTextWhenPlainTextIsMissing() throws {
  let directory = try temporaryDirectory()
  let capture = ClipboardCapture(assetStore: AssetStore(root: directory.appending(path: "Assets")))

  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(
        pasteboardType: ClipboardContentType.html,
        data: Data("<article>今天 &amp; 明天 <b>整理</b></article>".utf8)
      )
    ],
    sourceApp: nil
  )
  let item = try #require(captured)

  #expect(item.primaryType == ClipboardContentType.html)
  #expect(item.displayText == "今天 & 明天 整理")
  #expect(item.searchText == "今天 & 明天 整理")
}

@Test
func captureStoresImagesAsAssetsWithoutSearchText() throws {
  let directory = try temporaryDirectory()
  let assetStore = AssetStore(root: directory.appending(path: "Assets"))
  let capture = ClipboardCapture(assetStore: assetStore)
  let imageData = try onePixelPNG()

  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(pasteboardType: ClipboardContentType.png, data: imageData)
    ],
    sourceApp: "screenshot"
  )
  let item = try #require(captured)

  #expect(item.primaryType == ClipboardContentType.png)
  #expect(item.displayText == "图片")
  #expect(item.searchText.isEmpty)
  #expect(item.contents.count == 1)
  #expect(item.contents[0].inlineData == nil)
  #expect(item.contents[0].assetPath != nil)
  #expect(item.contents[0].imageWidth == 1)
  #expect(item.contents[0].imageHeight == 1)
  #expect(try assetStore.read(item.contents[0].assetPath!) == imageData)
}

@Test
func captureKeepsRTFButDoesNotIndexRichTextBody() throws {
  let directory = try temporaryDirectory()
  let capture = ClipboardCapture(assetStore: AssetStore(root: directory.appending(path: "Assets")))
  let rtfData = Data("{\\rtf1\\ansi 富文本}".utf8)

  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(pasteboardType: ClipboardContentType.rtf, data: rtfData)
    ],
    sourceApp: nil
  )
  let item = try #require(captured)

  #expect(item.primaryType == ClipboardContentType.rtf)
  #expect(item.displayText == "富文本")
  #expect(item.searchText.isEmpty)
  #expect(item.contents[0].inlineData == rtfData)
}

@Test
func captureNormalizesAndDeduplicatesTypes() throws {
  let directory = try temporaryDirectory()
  let capture = ClipboardCapture(assetStore: AssetStore(root: directory.appending(path: "Assets")))

  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(pasteboardType: ClipboardContentType.legacyPlainText, data: Data("旧类型".utf8)),
      ClipboardRawContent(pasteboardType: ClipboardContentType.plainText, data: Data("新类型".utf8))
    ],
    sourceApp: nil
  )
  let item = try #require(captured)

  #expect(item.contents.count == 1)
  #expect(item.contents[0].pasteboardType == ClipboardContentType.plainText)
  #expect(item.displayText == "旧类型")
}

@Test
func capturePreservesMultipleFileURLs() throws {
  let directory = try temporaryDirectory()
  let capture = ClipboardCapture(assetStore: AssetStore(root: directory.appending(path: "Assets")))
  let first = Data("file:///Users/me/one.txt".utf8)
  let second = Data("file:///Users/me/two.txt".utf8)

  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(pasteboardType: ClipboardContentType.fileURL, data: first),
      ClipboardRawContent(pasteboardType: ClipboardContentType.fileURL, data: second),
      ClipboardRawContent(pasteboardType: ClipboardContentType.fileURL, data: first)
    ],
    sourceApp: "com.apple.finder"
  )
  let item = try #require(captured)

  #expect(item.contents.map(\.pasteboardType) == [
    ClipboardContentType.fileURL,
    ClipboardContentType.fileURL
  ])
  #expect(item.contents.map(\.inlineData) == [first, second])
  #expect(item.searchText.contains("one.txt"))
  #expect(item.searchText.contains("two.txt"))
}

@Test
func captureKeepsSearchTextWhenLongUTF8TextIsTruncated() throws {
  let directory = try temporaryDirectory()
  let capture = ClipboardCapture(
    policy: StoragePolicy(textInlineLimit: 16, previewLimit: 12, searchTextLimit: 17),
    assetStore: AssetStore(root: directory.appending(path: "Assets"))
  )

  let text = String(repeating: "数据库长文本", count: 100)
  let captured = try capture.makeItem(
    contents: [
      ClipboardRawContent(pasteboardType: ClipboardContentType.plainText, data: Data(text.utf8))
    ],
    sourceApp: nil
  )
  let item = try #require(captured)

  #expect(!item.displayText.isEmpty)
  #expect(!item.searchText.isEmpty)
  #expect(item.searchText.contains("数据库"))
  #expect(item.contents.first?.assetPath != nil)
}

@Test
func pasteboardCaptureRulesIgnorePasteboardWithoutEnabledTypesOrWithIgnoredTypes() {
  let rules = ClipboardPasteboardCaptureRules(
    enabledTypes: [ClipboardContentType.plainText],
    ignoredTypes: ["secret.type"]
  )

  #expect(rules.shouldIgnorePasteboard(types: ["custom.only"]))
  #expect(rules.shouldIgnorePasteboard(types: [ClipboardContentType.plainText, "secret.type"]))
  #expect(!rules.shouldIgnorePasteboard(types: [ClipboardContentType.plainText, "custom.sidecar"]))
}

@Test
func pasteboardCaptureRulesSkipEmptyPlainTextUnlessRichTextPayloadExists() {
  let rules = ClipboardPasteboardCaptureRules()

  #expect(rules.selectedItemTypes(
    from: [ClipboardContentType.plainText],
    hasEmptyPlainText: true,
    hasRichTextPayload: false
  ).isEmpty)

  #expect(rules.selectedItemTypes(
    from: [ClipboardContentType.plainText, ClipboardContentType.rtf],
    hasEmptyPlainText: true,
    hasRichTextPayload: true
  ) == [ClipboardContentType.plainText, ClipboardContentType.rtf])
}

@Test
func pasteboardCaptureRulesAllowOnlySupportedEnabledTypes() {
  let rules = ClipboardPasteboardCaptureRules(
    enabledTypes: [ClipboardContentType.plainText]
  )

  let selected = rules.selectedItemTypes(
    from: [
      ClipboardContentType.plainText,
      ClipboardContentType.html,
      "dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu",
      "com.microsoft.ole.source.example",
      ClipboardPasteboardCaptureRules.microsoftObjectLink,
      ClipboardPasteboardCaptureRules.microsoftLinkSource,
      ClipboardPasteboardCaptureRules.pdf,
      "custom.sidecar",
      "com.apple.WebKit.custom-pasteboard-data"
    ],
    hasEmptyPlainText: false,
    hasRichTextPayload: false
  )

  #expect(selected == [ClipboardContentType.plainText])
}

@Test
func runtimePerformancePolicyDetectsSlowCaptureSamples() {
  let policy = ClipboardRuntimePerformancePolicy(
    pasteboardReadWarningMilliseconds: 10,
    coreInsertWarningMilliseconds: 20,
    totalCaptureWarningMilliseconds: 30
  )

  #expect(!policy.captureExceededWarningThreshold(ClipboardCapturePerformanceSample(
    typeCount: 2,
    readMilliseconds: 10,
    insertMilliseconds: 20,
    totalMilliseconds: 30
  )))
  #expect(policy.captureExceededWarningThreshold(ClipboardCapturePerformanceSample(
    typeCount: 2,
    readMilliseconds: 10.1,
    insertMilliseconds: 20,
    totalMilliseconds: 30
  )))
  #expect(policy.captureExceededWarningThreshold(ClipboardCapturePerformanceSample(
    typeCount: 2,
    readMilliseconds: 10,
    insertMilliseconds: 20.1,
    totalMilliseconds: 30
  )))
  #expect(policy.captureExceededWarningThreshold(ClipboardCapturePerformanceSample(
    typeCount: 2,
    readMilliseconds: 10,
    insertMilliseconds: 20,
    totalMilliseconds: 30.1
  )))
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func utcCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}

private func date(_ value: String, calendar: Calendar) throws -> Date {
  let formatter = ISO8601DateFormatter()
  formatter.timeZone = calendar.timeZone
  guard let date = formatter.date(from: value) else {
    throw CocoaError(.fileReadCorruptFile)
  }
  return date
}

private func onePixelPNG() throws -> Data {
  guard let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=") else {
    throw CocoaError(.fileReadCorruptFile)
  }

  return data
}
