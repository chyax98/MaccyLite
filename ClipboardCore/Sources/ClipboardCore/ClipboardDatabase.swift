import Foundation
import GRDB

public enum ClipboardDatabaseError: Error, Sendable {
  case insertedItemMissing(String)
}

public struct ClipboardDatabaseHealthReport: Sendable, Equatable {
  public var integrityCheck: String
  public var foreignKeyViolationCount: Int
  public var itemCount: Int
  public var contentCount: Int
  public var searchIndexCount: Int
  public var trigramIndexCount: Int
  public var missingSearchIndexCount: Int
  public var missingTrigramIndexCount: Int
  public var orphanSearchIndexCount: Int
  public var orphanTrigramIndexCount: Int

  public var isHealthy: Bool {
    integrityCheck == "ok" &&
      foreignKeyViolationCount == 0 &&
      missingSearchIndexCount == 0 &&
      missingTrigramIndexCount == 0 &&
      orphanSearchIndexCount == 0 &&
      orphanTrigramIndexCount == 0
  }

  public init(
    integrityCheck: String,
    foreignKeyViolationCount: Int,
    itemCount: Int,
    contentCount: Int,
    searchIndexCount: Int,
    trigramIndexCount: Int,
    missingSearchIndexCount: Int,
    missingTrigramIndexCount: Int,
    orphanSearchIndexCount: Int,
    orphanTrigramIndexCount: Int
  ) {
    self.integrityCheck = integrityCheck
    self.foreignKeyViolationCount = foreignKeyViolationCount
    self.itemCount = itemCount
    self.contentCount = contentCount
    self.searchIndexCount = searchIndexCount
    self.trigramIndexCount = trigramIndexCount
    self.missingSearchIndexCount = missingSearchIndexCount
    self.missingTrigramIndexCount = missingTrigramIndexCount
    self.orphanSearchIndexCount = orphanSearchIndexCount
    self.orphanTrigramIndexCount = orphanTrigramIndexCount
  }
}

public final class ClipboardDatabase: @unchecked Sendable {
  private let writer: DatabaseWriter
  private let recentSearchScope = 5_000

  public init(path: URL) throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode = WAL")
      try db.execute(sql: "PRAGMA synchronous = NORMAL")
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }

    writer = try DatabasePool(path: path.path, configuration: configuration)
    try Self.migrator.migrate(writer)
  }

  @discardableResult
  public func insert(_ item: ClipboardItemDraft) throws -> ClipboardStoredItem {
    try writer.write { db in
      try db.execute(
        sql: """
        INSERT INTO clipboard_items
          (id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count)
        VALUES
          (?, ?, ?, ?, ?, ?, 0, 1)
        """,
        arguments: [
          item.id,
          item.copiedAt.timeIntervalSince1970,
          item.sourceApp,
          item.primaryType,
          item.displayText,
          item.searchText
        ]
      )

      for content in item.contents {
        try db.execute(
          sql: """
          INSERT INTO clipboard_contents
            (
              item_id, pasteboard_type, byte_count, inline_data, asset_path, content_hash,
              image_width, image_height, thumbnail_path
            )
          VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
          arguments: [
            item.id,
            content.pasteboardType,
            content.byteCount,
            content.inlineData,
            content.assetPath,
            content.contentHash,
            content.imageWidth,
            content.imageHeight,
            content.thumbnailPath
          ]
        )
      }

      try db.execute(
        sql: "INSERT INTO clipboard_search(item_id, text) VALUES (?, ?)",
        arguments: [item.id, item.searchText]
      )

      try db.execute(
        sql: "INSERT INTO clipboard_trigram(item_id, text) VALUES (?, ?)",
        arguments: [item.id, item.searchText]
      )

      guard let stored = try storedItem(id: item.id, db: db) else {
        throw ClipboardDatabaseError.insertedItemMissing(item.id)
      }

      return stored
    }
  }

  public func setPinned(_ isPinned: Bool, itemID: String) throws {
    try writer.write { db in
      try db.execute(
        sql: "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?",
        arguments: [isPinned ? 1 : 0, itemID]
      )
    }
  }

  public func delete(itemID: String) throws {
    try writer.write { db in
      try db.execute(sql: "DELETE FROM clipboard_search WHERE item_id = ?", arguments: [itemID])
      try db.execute(sql: "DELETE FROM clipboard_trigram WHERE item_id = ?", arguments: [itemID])
      try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [itemID])
    }
  }

  public func latest(limit: Int = 50, offset: Int = 0) throws -> [ClipboardListItem] {
    try writer.read { db in
      try fetchListItems(
        db,
        sql: """
        SELECT \(listItemColumns(alias: "i"))
        FROM clipboard_items i
        ORDER BY is_pinned DESC, copied_at DESC
        LIMIT ? OFFSET ?
        """,
        arguments: [limit, offset]
      )
    }
  }

  public func latestStored(limit: Int = 50, offset: Int = 0) throws -> [ClipboardStoredItem] {
    try writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count
        FROM clipboard_items
        ORDER BY is_pinned DESC, copied_at DESC
        LIMIT ? OFFSET ?
        """,
        arguments: [limit, offset]
      )

      return try rows.map { try storedItem(from: $0, db: db) }
    }
  }

  public func search(_ query: String, limit: Int = 50) throws -> [ClipboardListItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return try latest(limit: limit)
    }

    return try writer.read { db in
      let recent = try recentLikeSearch(db, query: trimmed, limit: limit)
      if recent.count >= limit {
        return recent
      }

      if trimmed.count <= 2 {
        let expanded = try fullLikeSearch(db, query: trimmed, limit: limit)
        return mergeSearchResults(primary: recent, secondary: expanded, limit: limit)
      }

      let useTrigram = containsCJK(trimmed)
      let table = useTrigram ? "clipboard_trigram" : "clipboard_search"
      let expanded = try fetchListItems(
        db,
        sql: """
        SELECT \(listItemColumns(alias: "i"))
        FROM \(table) s
        JOIN clipboard_items i ON i.id = s.item_id
        WHERE s.text MATCH ?
        ORDER BY
          CASE
            WHEN i.search_text = ? COLLATE NOCASE THEN 0
            WHEN i.search_text LIKE ? ESCAPE '\\' THEN 1
            WHEN i.search_text LIKE ? ESCAPE '\\' THEN 2
            ELSE 3
          END,
          i.copied_at DESC
        LIMIT ?
        """,
        arguments: [ftsQuery(trimmed, prefixTokens: !useTrigram), trimmed, prefixPattern(trimmed), likePattern(trimmed), limit]
      )

      return mergeSearchResults(primary: recent, secondary: expanded, limit: limit)
    }
  }

  public func searchStored(_ query: String, limit: Int = 50) throws -> [ClipboardStoredItem] {
    let results = try search(query, limit: limit)
    return try writer.read { db in
      try results.compactMap { result in
        try storedItem(id: result.id, db: db)
      }
    }
  }

  public func item(id: String) throws -> ClipboardStoredItem? {
    try writer.read { db in
      try storedItem(id: id, db: db)
    }
  }

  public func items(from start: Date, to end: Date) throws -> [ClipboardStoredItem] {
    try writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count
        FROM clipboard_items
        WHERE copied_at >= ? AND copied_at < ?
        ORDER BY copied_at ASC
        """,
        arguments: [start.timeIntervalSince1970, end.timeIntervalSince1970]
      )

      return try rows.map { row in
        try storedItem(from: row, db: db)
      }
    }
  }

  public func itemCount(from start: Date, to end: Date) throws -> Int {
    try writer.read { db in
      try Int.fetchOne(
        db,
        sql: """
        SELECT COUNT(*)
        FROM clipboard_items
        WHERE copied_at >= ? AND copied_at < ?
        """,
        arguments: [start.timeIntervalSince1970, end.timeIntervalSince1970]
      ) ?? 0
    }
  }

  public func items(from start: Date, to end: Date, limit: Int, offset: Int) throws -> [ClipboardStoredItem] {
    try writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count
        FROM clipboard_items
        WHERE copied_at >= ? AND copied_at < ?
        ORDER BY copied_at ASC
        LIMIT ? OFFSET ?
        """,
        arguments: [start.timeIntervalSince1970, end.timeIntervalSince1970, limit, offset]
      )

      return try rows.map { row in
        try storedItem(from: row, db: db)
      }
    }
  }

  public func content(for itemID: String, type: String? = nil) throws -> ClipboardStoredContent? {
    try writer.read { db in
      let sql: String
      let arguments: StatementArguments
      if let type {
        sql = """
        SELECT
          pasteboard_type, byte_count, inline_data, asset_path, content_hash,
          image_width, image_height, thumbnail_path
        FROM clipboard_contents
        WHERE item_id = ? AND pasteboard_type = ?
        ORDER BY id ASC
        LIMIT 1
        """
        arguments = [itemID, type]
      } else {
        sql = """
        SELECT
          pasteboard_type, byte_count, inline_data, asset_path, content_hash,
          image_width, image_height, thumbnail_path
        FROM clipboard_contents
        WHERE item_id = ?
        ORDER BY id ASC
        LIMIT 1
        """
        arguments = [itemID]
      }

      guard let row = try Row.fetchOne(db, sql: sql, arguments: arguments) else {
        return nil
      }

      return storedContent(from: row)
    }
  }

  public func referencedAssetPaths() throws -> Set<String> {
    try writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT asset_path AS path FROM clipboard_contents WHERE asset_path IS NOT NULL
        UNION
        SELECT thumbnail_path AS path FROM clipboard_contents WHERE thumbnail_path IS NOT NULL
        """
      )
      return Set(rows.compactMap { row in row["path"] as String? })
    }
  }

  public func trimUnpinned(maxCount: Int) throws {
    guard maxCount >= 0 else {
      return
    }

    try writer.write { db in
      try db.execute(
        sql: """
        DELETE FROM clipboard_search
        WHERE item_id IN (
          SELECT id
          FROM clipboard_items
          WHERE is_pinned = 0
          ORDER BY copied_at DESC
          LIMIT -1 OFFSET ?
        )
        """,
        arguments: [maxCount]
      )
      try db.execute(
        sql: """
        DELETE FROM clipboard_trigram
        WHERE item_id IN (
          SELECT id
          FROM clipboard_items
          WHERE is_pinned = 0
          ORDER BY copied_at DESC
          LIMIT -1 OFFSET ?
        )
        """,
        arguments: [maxCount]
      )
      try db.execute(
        sql: """
        DELETE FROM clipboard_items
        WHERE id IN (
          SELECT id
          FROM clipboard_items
          WHERE is_pinned = 0
          ORDER BY copied_at DESC
          LIMIT -1 OFFSET ?
        )
        """,
        arguments: [maxCount]
      )
    }
  }

  public func pendingThumbnailJobs(limit: Int = 100) throws -> [ImageThumbnailJob] {
    try writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT content_hash, pasteboard_type, asset_path, image_width, image_height
        FROM clipboard_contents
        WHERE asset_path IS NOT NULL
          AND thumbnail_path IS NULL
          AND pasteboard_type IN (?, ?, ?, ?)
        ORDER BY id ASC
        LIMIT ?
        """,
        arguments: [
          ClipboardContentType.png,
          ClipboardContentType.tiff,
          ClipboardContentType.jpeg,
          ClipboardContentType.heic,
          limit
        ]
      )

      return rows.compactMap { row in
        guard let assetPath = row["asset_path"] as String? else {
          return nil
        }

        return ImageThumbnailJob(
          contentHash: row["content_hash"],
          pasteboardType: row["pasteboard_type"],
          assetPath: assetPath,
          imageWidth: row["image_width"],
          imageHeight: row["image_height"]
        )
      }
    }
  }

  public func markThumbnailGenerated(contentHash: String, thumbnailPath: String) throws {
    try writer.write { db in
      try db.execute(
        sql: "UPDATE clipboard_contents SET thumbnail_path = ? WHERE content_hash = ?",
        arguments: [thumbnailPath, contentHash]
      )
    }
  }

  public func recordExport(day: Date, path: String, itemCount: Int) throws {
    let dayKey = Self.dayKey(day)
    try writer.write { db in
      try db.execute(
        sql: """
        INSERT INTO daily_exports(day, path, item_count, exported_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(day) DO UPDATE SET
          path = excluded.path,
          item_count = excluded.item_count,
          exported_at = excluded.exported_at
        """,
        arguments: [dayKey, path, itemCount, Date.now.timeIntervalSince1970]
      )
    }
  }

  public func exportRecord(day: Date) throws -> DailyExportRecord? {
    let dayKey = Self.dayKey(day)
    return try writer.read { db in
      guard let row = try Row.fetchOne(
        db,
        sql: """
        SELECT day, path, item_count, exported_at
        FROM daily_exports
        WHERE day = ?
        """,
        arguments: [dayKey]
      ) else {
        return nil
      }

      return DailyExportRecord(
        day: row["day"],
        path: row["path"],
        itemCount: row["item_count"],
        exportedAt: Date(timeIntervalSince1970: row["exported_at"])
      )
    }
  }

  public func healthReport() throws -> ClipboardDatabaseHealthReport {
    try writer.read { db in
      ClipboardDatabaseHealthReport(
        integrityCheck: try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? "unknown",
        foreignKeyViolationCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pragma_foreign_key_check") ?? 0,
        itemCount: try count(db, table: "clipboard_items"),
        contentCount: try count(db, table: "clipboard_contents"),
        searchIndexCount: try count(db, table: "clipboard_search"),
        trigramIndexCount: try count(db, table: "clipboard_trigram"),
        missingSearchIndexCount: try scalarCount(
          db,
          """
          SELECT COUNT(*)
          FROM clipboard_items i
          LEFT JOIN clipboard_search s ON s.item_id = i.id
          WHERE s.item_id IS NULL
          """
        ),
        missingTrigramIndexCount: try scalarCount(
          db,
          """
          SELECT COUNT(*)
          FROM clipboard_items i
          LEFT JOIN clipboard_trigram s ON s.item_id = i.id
          WHERE s.item_id IS NULL
          """
        ),
        orphanSearchIndexCount: try scalarCount(
          db,
          """
          SELECT COUNT(*)
          FROM clipboard_search s
          LEFT JOIN clipboard_items i ON i.id = s.item_id
          WHERE i.id IS NULL
          """
        ),
        orphanTrigramIndexCount: try scalarCount(
          db,
          """
          SELECT COUNT(*)
          FROM clipboard_trigram s
          LEFT JOIN clipboard_items i ON i.id = s.item_id
          WHERE i.id IS NULL
          """
        )
      )
    }
  }

  public func rebuildSearchIndexes() throws {
    try writer.write { db in
      try db.execute(sql: "DELETE FROM clipboard_search")
      try db.execute(sql: "DELETE FROM clipboard_trigram")
      try db.execute(sql: """
      INSERT INTO clipboard_search(item_id, text)
      SELECT id, search_text FROM clipboard_items
      """)
      try db.execute(sql: """
      INSERT INTO clipboard_trigram(item_id, text)
      SELECT id, search_text FROM clipboard_items
      """)
    }
  }

  private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("createClipboardCore") { db in
      try db.execute(sql: """
      CREATE TABLE clipboard_items (
        id TEXT PRIMARY KEY NOT NULL,
        copied_at REAL NOT NULL,
        source_app TEXT,
        primary_type TEXT NOT NULL,
        display_text TEXT NOT NULL,
        search_text TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        copy_count INTEGER NOT NULL DEFAULT 1
      );

      CREATE TABLE clipboard_contents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
        pasteboard_type TEXT NOT NULL,
        byte_count INTEGER NOT NULL,
        inline_data BLOB,
        asset_path TEXT,
        content_hash TEXT NOT NULL,
        image_width INTEGER,
        image_height INTEGER,
        thumbnail_path TEXT
      );

      CREATE INDEX clipboard_items_copied_at
      ON clipboard_items(copied_at DESC);

      CREATE INDEX clipboard_items_pinned_copied_at
      ON clipboard_items(is_pinned DESC, copied_at DESC);

      CREATE INDEX clipboard_items_source_app
      ON clipboard_items(source_app);

      CREATE INDEX clipboard_contents_item_id
      ON clipboard_contents(item_id);

      CREATE INDEX clipboard_contents_asset_path
      ON clipboard_contents(asset_path);

      CREATE INDEX clipboard_contents_content_hash
      ON clipboard_contents(content_hash);

      CREATE INDEX clipboard_contents_thumbnail_path
      ON clipboard_contents(thumbnail_path);

      CREATE TABLE daily_exports (
        day TEXT PRIMARY KEY NOT NULL,
        path TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        exported_at REAL NOT NULL
      );

      CREATE VIRTUAL TABLE clipboard_search
      USING fts5(item_id UNINDEXED, text, tokenize = 'unicode61');

      CREATE VIRTUAL TABLE clipboard_trigram
      USING fts5(item_id UNINDEXED, text, tokenize = 'trigram');
      """)
    }

    return migrator
  }

  private func fetchListItems(
    _ db: Database,
    sql: String,
    arguments: StatementArguments
  ) throws -> [ClipboardListItem] {
    try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
      let hasImage = (row["has_image"] as Int?) ?? 0
      return ClipboardListItem(
        id: row["id"],
        copiedAt: Date(timeIntervalSince1970: row["copied_at"]),
        sourceApp: row["source_app"],
        primaryType: row["primary_type"],
        displayText: row["display_text"],
        isPinned: (row["is_pinned"] as Int) != 0,
        copyCount: row["copy_count"],
        hasImage: hasImage != 0
      )
    }
  }

  private func count(_ db: Database, table: String) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
  }

  private func scalarCount(_ db: Database, _ sql: String) throws -> Int {
    try Int.fetchOne(db, sql: sql) ?? 0
  }

  private func recentLikeSearch(_ db: Database, query: String, limit: Int) throws -> [ClipboardListItem] {
    try fetchListItems(
      db,
      sql: """
      SELECT \(listItemColumns(alias: "i"))
      FROM (
        SELECT id, copied_at, source_app, primary_type, display_text, is_pinned, copy_count, search_text
        FROM clipboard_items
        ORDER BY copied_at DESC
        LIMIT ?
      ) i
      WHERE search_text LIKE ? ESCAPE '\\'
      ORDER BY
        CASE
          WHEN search_text = ? COLLATE NOCASE THEN 0
          WHEN search_text LIKE ? ESCAPE '\\' THEN 1
          ELSE 2
        END,
        copied_at DESC
      LIMIT ?
      """,
      arguments: [recentSearchScope, likePattern(query), query, prefixPattern(query), limit]
    )
  }

  private func fullLikeSearch(_ db: Database, query: String, limit: Int) throws -> [ClipboardListItem] {
    try fetchListItems(
      db,
      sql: """
      SELECT \(listItemColumns(alias: "i"))
      FROM clipboard_items i
      WHERE search_text LIKE ? ESCAPE '\\'
      ORDER BY
        CASE
          WHEN i.search_text = ? COLLATE NOCASE THEN 0
          WHEN i.search_text LIKE ? ESCAPE '\\' THEN 1
          ELSE 2
        END,
        i.copied_at DESC
      LIMIT ?
      """,
      arguments: [likePattern(query), query, prefixPattern(query), limit]
    )
  }

  private func mergeSearchResults(
    primary: [ClipboardListItem],
    secondary: [ClipboardListItem],
    limit: Int
  ) -> [ClipboardListItem] {
    var seen = Set<String>()
    var merged: [ClipboardListItem] = []

    for item in primary + secondary where !seen.contains(item.id) {
      seen.insert(item.id)
      merged.append(item)
      if merged.count == limit {
        break
      }
    }

    return merged
  }

  private func listItemColumns(alias: String? = nil) -> String {
    let prefix = alias.map { "\($0)." } ?? ""
    return """
    \(prefix)id,
    \(prefix)copied_at,
    \(prefix)source_app,
    \(prefix)primary_type,
    \(prefix)display_text,
    \(prefix)is_pinned,
    \(prefix)copy_count,
    EXISTS (
      SELECT 1
      FROM clipboard_contents c
      WHERE c.item_id = \(prefix)id
        AND c.pasteboard_type IN (
          '\(ClipboardContentType.png)',
          '\(ClipboardContentType.tiff)',
          '\(ClipboardContentType.jpeg)',
          '\(ClipboardContentType.heic)'
        )
    ) AS has_image
    """
  }

  private func ftsQuery(_ query: String, prefixTokens: Bool) -> String {
    let tokens = ftsTokens(query, splitPunctuation: prefixTokens)

    guard !tokens.isEmpty else {
      return ftsTerm(query)
    }

    return tokens
      .map { prefixTokens ? ftsPrefixTerm($0) : ftsTerm($0) }
      .joined(separator: " ")
  }

  private func ftsTokens(_ query: String, splitPunctuation: Bool) -> [String] {
    let separators: (Character) -> Bool = { character in
      splitPunctuation
        ? !character.isLetter && !character.isNumber
        : character.isWhitespace
    }

    return query
      .split(whereSeparator: separators)
      .map(String.init)
      .filter { !$0.isEmpty }
  }

  private func ftsTerm(_ token: String) -> String {
    "\"\(token.replacingOccurrences(of: "\"", with: "\"\""))\""
  }

  private func ftsPrefixTerm(_ token: String) -> String {
    "\(token.lowercased())*"
  }

  private func likePattern(_ query: String) -> String {
    "%\(query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
  }

  private func prefixPattern(_ query: String) -> String {
    "\(query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
  }

  private func contents(for itemID: String, db: Database) throws -> [ClipboardStoredContent] {
    let rows = try Row.fetchAll(
      db,
      sql: """
      SELECT
        pasteboard_type, byte_count, inline_data, asset_path, content_hash,
        image_width, image_height, thumbnail_path
      FROM clipboard_contents
      WHERE item_id = ?
      ORDER BY id ASC
      """,
      arguments: [itemID]
    )

    return rows.map(storedContent(from:))
  }

  private func storedItem(id: String, db: Database) throws -> ClipboardStoredItem? {
    guard let row = try Row.fetchOne(
      db,
      sql: """
      SELECT id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count
      FROM clipboard_items
      WHERE id = ?
      """,
      arguments: [id]
    ) else {
      return nil
    }

    return try storedItem(from: row, db: db)
  }

  private func storedItem(from row: Row, db: Database) throws -> ClipboardStoredItem {
    let id: String = row["id"]
    return try ClipboardStoredItem(
      id: id,
      copiedAt: Date(timeIntervalSince1970: row["copied_at"]),
      sourceApp: row["source_app"],
      primaryType: row["primary_type"],
      displayText: row["display_text"],
      searchText: row["search_text"],
      isPinned: (row["is_pinned"] as Int) != 0,
      copyCount: row["copy_count"],
      contents: contents(for: id, db: db)
    )
  }

  private func storedContent(from row: Row) -> ClipboardStoredContent {
    ClipboardStoredContent(
      pasteboardType: row["pasteboard_type"],
      byteCount: row["byte_count"],
      inlineData: row["inline_data"],
      assetPath: row["asset_path"],
      contentHash: row["content_hash"],
      imageWidth: row["image_width"],
      imageHeight: row["image_height"],
      thumbnailPath: row["thumbnail_path"]
    )
  }

  private func containsCJK(_ string: String) -> Bool {
    string.unicodeScalars.contains { scalar in
      (0x4E00...0x9FFF).contains(scalar.value)
    }
  }

  static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let start = calendar.startOfDay(for: date)
    return dayFormatter.string(from: start)
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}
