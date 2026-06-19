import Foundation

public struct DailyExportSchedulePolicy: Sendable, Equatable {
  public var hour: Int
  public var minute: Int
  public var catchUpDays: Int
  public var calendar: Calendar

  public init(
    hour: Int,
    minute: Int,
    catchUpDays: Int,
    calendar: Calendar = .current
  ) {
    self.hour = min(max(hour, 0), 23)
    self.minute = min(max(minute, 0), 59)
    self.catchUpDays = min(max(catchUpDays, 0), 30)
    self.calendar = calendar
  }

  public func nextFireDate(after now: Date) -> Date? {
    var components = calendar.dateComponents([.year, .month, .day], from: now)
    components.hour = hour
    components.minute = minute
    components.second = 0

    guard let today = calendar.date(from: components) else {
      return nil
    }

    if today > now {
      return today
    }

    return calendar.date(byAdding: .day, value: 1, to: today)
  }

  public func catchUpExportDays(before now: Date) -> [Date] {
    guard catchUpDays > 0 else {
      return []
    }

    return (1...catchUpDays).compactMap { offset in
      calendar.date(byAdding: .day, value: -offset, to: now)
    }
  }
}
