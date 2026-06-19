import ClipboardCore
import Defaults
import Foundation
import Logging

final class DailyExportScheduler {
  static let shared = DailyExportScheduler()

  private let logger = Logger(label: "com.local.MaccyLite.daily-export")
  private let calendar: Calendar = .current
  private let queue = DispatchQueue(label: "com.local.MaccyLite.daily-export", qos: .utility)
  private var observations: [Defaults.Observation] = []
  private var timer: Timer?

  private init() {}

  func start() {
    observeSettingsIfNeeded()
    if Defaults[.dailyExportEnabled] {
      queue.async { [weak self] in
        self?.catchUpMissingExports()
      }
    }
    reschedule()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  @discardableResult
  func exportToday() -> URL? {
    export(day: Date.now)?.url
  }

  func exportToday(completion: @escaping @MainActor (URL?) -> Void) {
    queue.async { [weak self] in
      let url = self?.exportToday()
      DispatchQueue.main.async {
        completion(url)
      }
    }
  }

  @discardableResult
  func exportYesterday() -> URL? {
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date.now) else {
      return nil
    }

    return export(day: yesterday)?.url
  }

  func exportYesterday(completion: @escaping @MainActor (URL?) -> Void) {
    queue.async { [weak self] in
      let url = self?.exportYesterday()
      DispatchQueue.main.async {
        completion(url)
      }
    }
  }

  private func observeSettingsIfNeeded() {
    guard observations.isEmpty else {
      return
    }

    observations = [
      Defaults.observe(.dailyExportEnabled) { [weak self] _ in self?.reschedule() },
      Defaults.observe(.dailyExportHour) { [weak self] _ in self?.reschedule() },
      Defaults.observe(.dailyExportMinute) { [weak self] _ in self?.reschedule() },
      Defaults.observe(.dailyExportCatchUpDays) { [weak self] _ in self?.reschedule() }
    ]
  }

  private func reschedule() {
    stop()

    guard Defaults[.dailyExportEnabled] else {
      return
    }

    scheduleNextExport()
  }

  private func catchUpMissingExports() {
    for day in schedulePolicy().catchUpExportDays(before: Date.now) {
      if exportAlreadyCurrent(day: day) {
        continue
      }
      _ = export(day: day)
    }
  }

  private func scheduleNextExport() {
    guard let fireDate = schedulePolicy().nextFireDate(after: Date.now) else {
      return
    }

    timer = Timer(
      fireAt: fireDate,
      interval: 0,
      target: self,
      selector: #selector(runScheduledExport),
      userInfo: nil,
      repeats: false
    )
    if let timer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  @objc
  private func runScheduledExport() {
    queue.async { [weak self] in
      guard let self else { return }
      _ = exportYesterday()

      if Defaults[.dailyExportCleanupOrphans] {
        _ = ClipboardCoreStore.shared.removeOrphanAssets()
      }

      DispatchQueue.main.async {
        self.scheduleNextExport()
      }
    }
  }

  private func export(day: Date) -> DailyExportResult? {
    if let result = ClipboardCoreStore.shared.export(day: day) {
      logger.info("Exported \(result.itemCount) clipboard items to \(result.url.path)")
      return result
    } else {
      logger.error("Failed to export clipboard items for \(day)")
      return nil
    }
  }

  private func exportAlreadyCurrent(day: Date) -> Bool {
    guard let record = ClipboardCoreStore.shared.exportRecord(day: day),
          FileManager.default.fileExists(atPath: record.path),
          let currentCount = ClipboardCoreStore.shared.exportItemCount(day: day, calendar: calendar) else {
      return false
    }

    return record.itemCount == currentCount
  }

  private func schedulePolicy() -> DailyExportSchedulePolicy {
    DailyExportSchedulePolicy(
      hour: Defaults[.dailyExportHour],
      minute: Defaults[.dailyExportMinute],
      catchUpDays: Defaults[.dailyExportCatchUpDays],
      calendar: calendar
    )
  }
}
