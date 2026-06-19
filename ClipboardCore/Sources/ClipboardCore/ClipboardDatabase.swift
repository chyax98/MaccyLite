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
  private static let maximumSearchQueryLength = 1_000

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
      let fingerprint = itemFingerprint(item)
      if !fingerprint.isEmpty, let existingID = try String.fetchOne(
        db,
        sql: """
        SELECT id
        FROM clipboard_items
        WHERE content_fingerprint = ?
        ORDER BY is_pinned DESC, copied_at DESC
        LIMIT 1
        """,
        arguments: [fingerprint]
      ) {
        try db.execute(
          sql: """
          UPDATE clipboard_items
          SET copied_at = ?,
              source_app = ?,
              primary_type = ?,
              display_text = ?,
              search_text = ?,
              content_fingerprint = ?,
              has_image = ?,
              copy_count = copy_count + 1
          WHERE id = ?
          """,
          arguments: [
            item.copiedAt.timeIntervalSince1970,
            item.sourceApp,
            item.primaryType,
            item.displayText,
            item.searchText,
            fingerprint,
            itemHasImage(item),
            existingID
          ]
        )
        try replacePayloadAndIndexes(for: existingID, with: item, db: db)

        guard let stored = try storedItem(id: existingID, db: db) else {
          throw ClipboardDatabaseError.insertedItemMissing(existingID)
        }

        return stored
      }

      try db.execute(
        sql: """
        INSERT INTO clipboard_items
          (
            id, copied_at, source_app, primary_type, display_text, search_text,
            content_fingerprint, has_image, is_pinned, copy_count
          )
        VALUES
          (?, ?, ?, ?, ?, ?, ?, ?, 0, 1)
        """,
        arguments: [
          item.id,
          item.copiedAt.timeIntervalSince1970,
          item.sourceApp,
          item.primaryType,
          item.displayText,
          item.searchText,
          fingerprint,
          itemHasImage(item)
        ]
      )

      try insertPayloadAndIndexes(for: item.id, from: item, db: db)

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
      try db.execute(sql: "DROP TABLE IF EXISTS temp.delete_candidates")
      try db.execute(sql: "CREATE TEMP TABLE delete_candidates(id TEXT PRIMARY KEY) WITHOUT ROWID")
      try db.execute(
        sql: """
        INSERT INTO delete_candidates(id)
          SELECT candidate.id
          FROM clipboard_items selected
          JOIN clipboard_items candidate
            ON selected.content_fingerprint IS NOT NULL
           AND selected.content_fingerprint != ''
           AND candidate.content_fingerprint = selected.content_fingerprint
          WHERE selected.id = ?
        """,
        arguments: [itemID]
      )
      try db.execute(
        sql: """
        INSERT OR IGNORE INTO delete_candidates(id)
        VALUES (?)
        """,
        arguments: [itemID]
      )
      try db.execute(sql: "DELETE FROM clipboard_search WHERE item_id IN (SELECT id FROM delete_candidates)")
      try db.execute(sql: "DELETE FROM clipboard_trigram WHERE item_id IN (SELECT id FROM delete_candidates)")
      try db.execute(sql: "DELETE FROM clipboard_items WHERE id IN (SELECT id FROM delete_candidates)")
      try db.execute(sql: "DROP TABLE IF EXISTS temp.delete_candidates")
    }
  }

  public func deleteUnpinned() throws {
    try writer.write { db in
      try db.execute(sql: "DROP TABLE IF EXISTS temp.delete_candidates")
      try db.execute(sql: "CREATE TEMP TABLE delete_candidates(id TEXT PRIMARY KEY) WITHOUT ROWID")
      try db.execute(sql: "INSERT INTO delete_candidates(id) SELECT id FROM clipboard_items WHERE is_pinned = 0")
      try db.execute(sql: "DELETE FROM clipboard_search WHERE item_id IN (SELECT id FROM delete_candidates)")
      try db.execute(sql: "DELETE FROM clipboard_trigram WHERE item_id IN (SELECT id FROM delete_candidates)")
      try db.execute(sql: "DELETE FROM clipboard_items WHERE id IN (SELECT id FROM delete_candidates)")
      try db.execute(sql: "DROP TABLE IF EXISTS temp.delete_candidates")
    }
  }

  public func deleteAll() throws {
    try writer.write { db in
      try db.execute(sql: "DELETE FROM clipboard_search")
      try db.execute(sql: "DELETE FROM clipboard_trigram")
      try db.execute(sql: "DELETE FROM clipboard_items")
    }
  }

  public func latestUnpinnedDisplayText() throws -> String? {
    try writer.read { db in
      try String.fetchOne(
        db,
        sql: """
        SELECT display_text
        FROM clipboard_items
        WHERE is_pinned = 0
        ORDER BY copied_at DESC
        LIMIT 1
        """
      )
    }
  }

  public func latest(limit: Int = 50, offset: Int = 0) throws -> [ClipboardListItem] {
    try writer.read { db in
      try fetchListItems(
        db,
        sql: """
        SELECT \(listItemColumns(alias: "i"))
        FROM clipboard_items i
        WHERE \(visibleFingerprintPredicate(alias: "i"))
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

      return try storedItems(from: rows, db: db)
    }
  }

  public func search(_ query: String, limit: Int = 50) throws -> [ClipboardListItem] {
    let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumSearchQueryLength))
    guard !trimmed.isEmpty else {
      return try latest(limit: limit)
    }

    return try writer.read { db in
      let recent = try recentLikeSearch(db, query: trimmed, limit: limit)
      if trimmed.count == 1 {
        return recent
      }

      if trimmed.count <= 2 {
        if recent.count >= limit {
          return recent
        }
        let full = try fullLikeSearch(db, query: trimmed, limit: limit)
        return mergeSearchResults(primary: recent, secondary: full, limit: limit)
      }

      if recent.count >= limit {
        return recent
      }

      let expanded = try ftsSearch(db, query: trimmed, limit: limit)
      return mergeSearchResults(primary: recent, secondary: expanded, limit: limit)
    }
  }

  public func searchStored(_ query: String, limit: Int = 50) throws -> [ClipboardStoredItem] {
    let results = try search(query, limit: limit)
    return try writer.read { db in
      try storedItems(ids: results.map(\.id), db: db)
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

      return try storedItems(from: rows, db: db)
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

  public func items(
    from start: Date,
    to end: Date,
    afterCopiedAt: Date? = nil,
    afterID: String? = nil,
    limit: Int
  ) throws -> [ClipboardStoredItem] {
    try writer.read { db in
      let cursorCopiedAt = afterCopiedAt?.timeIntervalSince1970
      let cursorID = afterID ?? ""
      let rows = try Row.fetchAll(
        db,
        sql: """
        SELECT id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count
        FROM clipboard_items
        WHERE copied_at >= ? AND copied_at < ?
          AND (? IS NULL OR copied_at > ? OR (copied_at = ? AND id > ?))
        ORDER BY copied_at ASC, id ASC
        LIMIT ?
        """,
        arguments: [
          start.timeIntervalSince1970,
          end.timeIntervalSince1970,
          cursorCopiedAt,
          cursorCopiedAt,
          cursorCopiedAt,
          cursorID,
          limit
        ]
      )

      return try storedItems(from: rows, db: db)
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
          image_width, image_height
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
          image_width, image_height
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
      try db.execute(sql: "DROP TABLE IF EXISTS temp.trim_candidates")
      try db.execute(sql: "CREATE TEMP TABLE trim_candidates(id TEXT PRIMARY KEY) WITHOUT ROWID")
      try db.execute(
        sql: """
        INSERT INTO trim_candidates(id)
          SELECT id
          FROM clipboard_items
          WHERE is_pinned = 0
          ORDER BY copied_at DESC
          LIMIT -1 OFFSET ?
        """,
        arguments: [maxCount]
      )
      try db.execute(
        sql: """
        DELETE FROM clipboard_search
        WHERE item_id IN (SELECT id FROM trim_candidates)
        """
      )
      try db.execute(
        sql: """
        DELETE FROM clipboard_trigram
        WHERE item_id IN (SELECT id FROM trim_candidates)
        """
      )
      try db.execute(
        sql: """
        DELETE FROM clipboard_items
        WHERE id IN (SELECT id FROM trim_candidates)
        """
      )
      try db.execute(sql: "DROP TABLE IF EXISTS temp.trim_candidates")
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
        image_height INTEGER
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

    migrator.registerMigration("addClipboardItemHasImage") { db in
      try db.execute(sql: """
      ALTER TABLE clipboard_items
      ADD COLUMN has_image INTEGER NOT NULL DEFAULT 0
      """)

      try db.execute(sql: """
      UPDATE clipboard_items
      SET has_image = 1
      WHERE id IN (
        SELECT item_id
        FROM clipboard_contents
        WHERE pasteboard_type IN (?, ?, ?, ?)
           OR image_width IS NOT NULL
           OR image_height IS NOT NULL
      )
      """, arguments: [
        ClipboardContentType.png,
        ClipboardContentType.tiff,
        ClipboardContentType.jpeg,
        ClipboardContentType.heic
      ])
    }

    migrator.registerMigration("addClipboardItemContentFingerprint") { db in
      try db.execute(sql: """
      ALTER TABLE clipboard_items
      ADD COLUMN content_fingerprint TEXT
      """)

      try db.execute(sql: """
      UPDATE clipboard_items
      SET content_fingerprint = (
        SELECT group_concat(pasteboard_type || ':' || byte_count || ':' || content_hash, char(10))
        FROM (
          SELECT pasteboard_type, byte_count, content_hash
          FROM clipboard_contents
          WHERE item_id = clipboard_items.id
          ORDER BY id ASC
        )
      )
      """)

      try db.execute(sql: """
      CREATE INDEX clipboard_items_content_fingerprint
      ON clipboard_items(content_fingerprint)
      """)
    }

    migrator.registerMigration("addClipboardItemExportOrderIndex") { db in
      try db.execute(sql: """
      CREATE INDEX clipboard_items_export_day_order
      ON clipboard_items(copied_at ASC, id ASC)
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
        hasImage: hasImage != 0,
        contentFingerprint: row["content_fingerprint"]
      )
    }
  }

  private func count(_ db: Database, table: String) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
  }

  private func scalarCount(_ db: Database, _ sql: String) throws -> Int {
    try Int.fetchOne(db, sql: sql) ?? 0
  }

  private func recentLikeSearch(
    _ db: Database,
    query: String,
    limit: Int
  ) throws -> [ClipboardListItem] {
    let candidateLimit = searchCandidateLimit(for: limit)
    return try fetchListItems(
      db,
      sql: """
      SELECT \(listItemColumns(alias: "i"))
      FROM (
        SELECT
          id, copied_at, source_app, primary_type, display_text, has_image,
          is_pinned, copy_count, search_text, content_fingerprint
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
        is_pinned DESC,
        copied_at DESC
      LIMIT ?
      """,
      arguments: [recentSearchScope, likePattern(query), query, prefixPattern(query), candidateLimit]
    )
  }

  private func fullLikeSearch(
    _ db: Database,
    query: String,
    limit: Int
  ) throws -> [ClipboardListItem] {
    let candidateLimit = searchCandidateLimit(for: limit)
    return try fetchListItems(
      db,
      sql: """
      SELECT \(listItemColumns(alias: "i"))
      FROM clipboard_items i
      WHERE i.search_text LIKE ? ESCAPE '\\'
      ORDER BY
        CASE
          WHEN i.search_text = ? COLLATE NOCASE THEN 0
          WHEN i.search_text LIKE ? ESCAPE '\\' THEN 1
          ELSE 2
        END,
        i.is_pinned DESC,
        i.copied_at DESC
      LIMIT ?
      """,
      arguments: [likePattern(query), query, prefixPattern(query), candidateLimit]
    )
  }

  private func ftsSearch(
    _ db: Database,
    query: String,
    limit: Int
  ) throws -> [ClipboardListItem] {
    let useTrigram = containsCJK(query)
    let table = useTrigram ? "clipboard_trigram" : "clipboard_search"
    let candidateLimit = searchCandidateLimit(for: limit)
    return try fetchListItems(
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
        i.is_pinned DESC,
        i.copied_at DESC
      LIMIT ?
      """,
      arguments: [ftsQuery(query, prefixTokens: !useTrigram), query, prefixPattern(query), likePattern(query), candidateLimit]
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
      if let fingerprint = item.contentFingerprint, !fingerprint.isEmpty {
        guard !seen.contains(fingerprint) else {
          continue
        }
        seen.insert(fingerprint)
      }
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
    \(prefix)has_image,
    \(prefix)is_pinned,
    \(prefix)copy_count,
    \(prefix)content_fingerprint
    """
  }

  private func searchCandidateLimit(for limit: Int) -> Int {
    max(limit, min(limit * 4, 500))
  }

  private func visibleFingerprintPredicate(alias: String) -> String {
    """
    (
      \(alias).content_fingerprint IS NULL
      OR \(alias).content_fingerprint = ''
      OR NOT EXISTS (
        SELECT 1
        FROM clipboard_items newer
        WHERE newer.content_fingerprint = \(alias).content_fingerprint
          AND (
            newer.is_pinned > \(alias).is_pinned
            OR (
              newer.is_pinned = \(alias).is_pinned
              AND (
                newer.copied_at > \(alias).copied_at
                OR (newer.copied_at = \(alias).copied_at AND newer.id > \(alias).id)
              )
            )
          )
      )
    )
    """
  }

  private func itemHasImage(_ item: ClipboardItemDraft) -> Bool {
    item.contents.contains { content in
      content.imageWidth != nil ||
        content.imageHeight != nil ||
        [
          ClipboardContentType.png,
          ClipboardContentType.tiff,
          ClipboardContentType.jpeg,
          ClipboardContentType.heic
        ].contains(content.pasteboardType)
    }
  }

  private func replacePayloadAndIndexes(
    for itemID: String,
    with item: ClipboardItemDraft,
    db: Database
  ) throws {
    try db.execute(sql: "DELETE FROM clipboard_contents WHERE item_id = ?", arguments: [itemID])
    try db.execute(sql: "DELETE FROM clipboard_search WHERE item_id = ?", arguments: [itemID])
    try db.execute(sql: "DELETE FROM clipboard_trigram WHERE item_id = ?", arguments: [itemID])
    try insertPayloadAndIndexes(for: itemID, from: item, db: db)
  }

  private func insertPayloadAndIndexes(
    for itemID: String,
    from item: ClipboardItemDraft,
    db: Database
  ) throws {
    for content in item.contents {
      try db.execute(
        sql: """
        INSERT INTO clipboard_contents
          (
            item_id, pasteboard_type, byte_count, inline_data, asset_path, content_hash,
            image_width, image_height
          )
        VALUES
          (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        arguments: [
          itemID,
          content.pasteboardType,
          content.byteCount,
          content.inlineData,
          content.assetPath,
          content.contentHash,
          content.imageWidth,
          content.imageHeight
        ]
      )
    }

    try db.execute(
      sql: "INSERT INTO clipboard_search(item_id, text) VALUES (?, ?)",
      arguments: [itemID, item.searchText]
    )

    try db.execute(
      sql: "INSERT INTO clipboard_trigram(item_id, text) VALUES (?, ?)",
      arguments: [itemID, item.searchText]
    )
  }

  private func itemFingerprint(_ item: ClipboardItemDraft) -> String {
    itemFingerprint(contents: item.contents.map {
      FingerprintContent(
        pasteboardType: $0.pasteboardType,
        byteCount: $0.byteCount,
        contentHash: $0.contentHash
      )
    })
  }

  private func itemFingerprint(contents: [FingerprintContent]) -> String {
    for types in fingerprintPriorityTypes {
      let matching = contents
        .filter { types.contains($0.pasteboardType) }
        .sorted { lhs, rhs in
          if lhs.pasteboardType != rhs.pasteboardType {
            return lhs.pasteboardType < rhs.pasteboardType
          }
          if lhs.contentHash != rhs.contentHash {
            return lhs.contentHash < rhs.contentHash
          }
          return lhs.byteCount < rhs.byteCount
        }
      if !matching.isEmpty {
        return matching
          .map { "\($0.pasteboardType):\($0.byteCount):\($0.contentHash)" }
          .joined(separator: "\n")
      }
    }

    return contents
      .filter { !$0.contentHash.isEmpty }
      .sorted { lhs, rhs in
        if lhs.pasteboardType != rhs.pasteboardType {
          return lhs.pasteboardType < rhs.pasteboardType
        }
        return lhs.contentHash < rhs.contentHash
      }
      .map { "\($0.pasteboardType):\($0.byteCount):\($0.contentHash)" }
      .joined(separator: "\n")
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

  private func storedItems(ids: [String], db: Database) throws -> [ClipboardStoredItem] {
    guard !ids.isEmpty else {
      return []
    }

    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
    let rows = try Row.fetchAll(
      db,
      sql: """
      SELECT id, copied_at, source_app, primary_type, display_text, search_text, is_pinned, copy_count
      FROM clipboard_items
      WHERE id IN (\(placeholders))
      """,
      arguments: StatementArguments(ids)
    )
    let itemsByID = Dictionary(uniqueKeysWithValues: try storedItems(from: rows, db: db).map { ($0.id, $0) })
    return ids.compactMap { itemsByID[$0] }
  }

  private func storedItems(from rows: [Row], db: Database) throws -> [ClipboardStoredItem] {
    let ids: [String] = rows.map { $0["id"] }
    let contentsByID = try contentsByItemID(itemIDs: ids, db: db)

    return rows.map { row in
      let id: String = row["id"]
      return storedItem(from: row, contents: contentsByID[id] ?? [])
    }
  }

  private func contentsByItemID(itemIDs: [String], db: Database) throws -> [String: [ClipboardStoredContent]] {
    guard !itemIDs.isEmpty else {
      return [:]
    }

    let placeholders = Array(repeating: "?", count: itemIDs.count).joined(separator: ",")
    let rows = try Row.fetchAll(
      db,
      sql: """
      SELECT
        item_id, pasteboard_type, byte_count, inline_data, asset_path, content_hash,
        image_width, image_height
      FROM clipboard_contents
      WHERE item_id IN (\(placeholders))
      ORDER BY item_id ASC, id ASC
      """,
      arguments: StatementArguments(itemIDs)
    )

    var grouped: [String: [ClipboardStoredContent]] = [:]
    for row in rows {
      let itemID: String = row["item_id"]
      grouped[itemID, default: []].append(storedContent(from: row))
    }
    return grouped
  }

  private func contents(for itemID: String, db: Database) throws -> [ClipboardStoredContent] {
    let rows = try Row.fetchAll(
      db,
      sql: """
      SELECT
        pasteboard_type, byte_count, inline_data, asset_path, content_hash,
        image_width, image_height
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
    return try storedItem(from: row, contents: contents(for: id, db: db))
  }

  private func storedItem(from row: Row, contents: [ClipboardStoredContent]) -> ClipboardStoredItem {
    let id: String = row["id"]
    return ClipboardStoredItem(
      id: id,
      copiedAt: Date(timeIntervalSince1970: row["copied_at"]),
      sourceApp: row["source_app"],
      primaryType: row["primary_type"],
      displayText: row["display_text"],
      searchText: row["search_text"],
      isPinned: (row["is_pinned"] as Int) != 0,
      copyCount: row["copy_count"],
      contents: contents
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
      imageHeight: row["image_height"]
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

private struct FingerprintContent {
  var pasteboardType: String
  var byteCount: Int
  var contentHash: String
}

private let fingerprintPriorityTypes: [Set<String>] = [
  [ClipboardContentType.plainText, ClipboardContentType.legacyPlainText],
  [ClipboardContentType.fileURL],
  [
    ClipboardContentType.png,
    ClipboardContentType.tiff,
    ClipboardContentType.jpeg,
    ClipboardContentType.heic
  ],
  [ClipboardContentType.html],
  [ClipboardContentType.rtf]
]
