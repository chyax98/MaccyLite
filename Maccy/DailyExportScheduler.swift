import ClipboardCore
import Foundation
import Logging

struct DailyExportOutcome {
  let url: URL?
  let errorMessage: String?

  var succeeded: Bool {
    url != nil && errorMessage == nil
  }

  static func success(_ result: DailyExportResult) -> DailyExportOutcome {
    DailyExportOutcome(url: result.url, errorMessage: nil)
  }

  static func failure(_ message: String) -> DailyExportOutcome {
    DailyExportOutcome(url: nil, errorMessage: message)
  }
}

final class DailyExportScheduler {
  static let shared = DailyExportScheduler()

  private let logger = Logger(label: "com.local.MaccyLite.daily-export")
  private let calendar: Calendar = .current
  private let queue = DispatchQueue(label: "com.local.MaccyLite.daily-export", qos: .utility)
  private var timer: Timer?

  private init() {}

  func start() {
    if AppPreferences.dailyExportEnabled {
      queue.async { [weak self] in
        self?.catchUpMissingExports()
      }
    }
    reschedule()
  }

  func stop() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.stop()
      }
      return
    }

    timer?.invalidate()
    timer = nil
  }

  @discardableResult
  func exportToday() -> DailyExportOutcome {
    export(day: Date.now)
  }

  func exportToday(completion: @escaping @MainActor (DailyExportOutcome) -> Void) {
    queue.async { [weak self] in
      let outcome = self?.exportToday() ?? .failure("导出器不可用")
      DispatchQueue.main.async {
        completion(outcome)
      }
    }
  }

  @discardableResult
  func exportYesterday() -> DailyExportOutcome {
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date.now) else {
      return .failure("无法计算昨天日期")
    }

    return export(day: yesterday)
  }

  func exportYesterday(completion: @escaping @MainActor (DailyExportOutcome) -> Void) {
    queue.async { [weak self] in
      let outcome = self?.exportYesterday() ?? .failure("导出器不可用")
      DispatchQueue.main.async {
        completion(outcome)
      }
    }
  }

  func reschedule() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.reschedule()
      }
      return
    }

    stop()

    guard AppPreferences.dailyExportEnabled else {
      return
    }

    scheduleNextExport()
  }

  private func catchUpMissingExports() {
    for day in schedulePolicy().missingExportDays(before: Date.now, isExportCurrent: exportAlreadyCurrent) {
      let outcome = export(day: day)
      if !outcome.succeeded {
        showBackgroundFailure(outcome)
        return
      }
    }
  }

  private func scheduleNextExport() {
    assert(Thread.isMainThread)

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
      let outcome = exportYesterday()
      if !outcome.succeeded {
        showBackgroundFailure(outcome)
      }

      if AppPreferences.dailyExportCleanupOrphans {
        _ = ClipboardCoreStore.shared.removeOrphanAssets()
      }

      DispatchQueue.main.async {
        self.scheduleNextExport()
      }
    }
  }

  private func export(day: Date) -> DailyExportOutcome {
    do {
      let result = try ClipboardCoreStore.shared.export(day: day)
      logger.info("Exported \(result.itemCount) clipboard items to \(result.url.path)")
      return .success(result)
    } catch {
      logger.error("Failed to export clipboard items for \(day): \(error.localizedDescription)")
      return .failure(error.localizedDescription)
    }
  }

  private func showBackgroundFailure(_ outcome: DailyExportOutcome) {
    DispatchQueue.main.async {
      let suffix = outcome.errorMessage.map { "：\($0)" } ?? ""
      AppState.shared.appDelegate?.showTransientStatus("每日导出失败\(suffix)")
    }
  }

  private func exportAlreadyCurrent(day: Date) -> Bool {
    let record = ClipboardCoreStore.shared.exportRecord(day: day)
    let fileExists = record.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let currentCount = ClipboardCoreStore.shared.exportItemCount(day: day, calendar: calendar)
    return schedulePolicy().exportIsCurrent(
      record: record,
      fileExists: fileExists,
      currentItemCount: currentCount
    )
  }

  private func schedulePolicy() -> DailyExportSchedulePolicy {
    DailyExportSchedulePolicy(
      hour: AppPreferences.dailyExportHour,
      minute: AppPreferences.dailyExportMinute,
      catchUpDays: AppPreferences.dailyExportCatchUpDays,
      calendar: calendar
    )
  }
}
