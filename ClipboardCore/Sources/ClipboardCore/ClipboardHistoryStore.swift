import Foundation

public final class ClipboardHistoryStore: @unchecked Sendable {
  private let database: ClipboardDatabase
  private let capture: ClipboardCapture

  public init(database: ClipboardDatabase, capture: ClipboardCapture) {
    self.database = database
    self.capture = capture
  }

  @discardableResult
  public func insert(
    contents: [ClipboardRawContent],
    sourceApp: String?,
    copiedAt: Date = .now
  ) throws -> ClipboardStoredItem? {
    guard let item = try capture.makeItem(
      contents: contents,
      sourceApp: sourceApp,
      copiedAt: copiedAt
    ) else {
      return nil
    }

    return try database.insert(item)
  }

  public func latest(limit: Int = 50, offset: Int = 0) throws -> [ClipboardStoredItem] {
    try database.latestStored(limit: limit, offset: offset)
  }

  public func latestList(limit: Int = 50, offset: Int = 0) throws -> [ClipboardListItem] {
    try database.latest(limit: limit, offset: offset)
  }

  public func search(_ query: String, limit: Int = 50) throws -> [ClipboardStoredItem] {
    try database.searchStored(query, limit: limit)
  }

  public func searchList(_ query: String, limit: Int = 50) throws -> [ClipboardListItem] {
    try database.search(query, limit: limit)
  }

  public func selectedItem(id: String) throws -> ClipboardStoredItem? {
    try database.item(id: id)
  }

  public func setPinned(_ isPinned: Bool, itemID: String) throws {
    try database.setPinned(isPinned, itemID: itemID)
  }

  public func delete(itemID: String) throws {
    try database.delete(itemID: itemID)
  }

  public func deleteUnpinned() throws {
    try database.deleteUnpinned()
  }

  public func deleteAll() throws {
    try database.deleteAll()
  }

  public func latestUnpinnedDisplayText() throws -> String? {
    try database.latestUnpinnedDisplayText()
  }

  public func trimUnpinned(maxCount: Int) throws {
    try database.trimUnpinned(maxCount: maxCount)
  }
}
