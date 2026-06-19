import Foundation

public struct DailyExportRecord: Sendable, Equatable {
  public var day: String
  public var path: String
  public var itemCount: Int
  public var exportedAt: Date

  public init(day: String, path: String, itemCount: Int, exportedAt: Date) {
    self.day = day
    self.path = path
    self.itemCount = itemCount
    self.exportedAt = exportedAt
  }
}
