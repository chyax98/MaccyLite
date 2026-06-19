import AppKit
import SwiftUI
import Defaults
import Settings

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.dailyExportCatchUpDays) private var dailyExportCatchUpDays
  @Default(.dailyExportCleanupOrphans) private var dailyExportCleanupOrphans
  @Default(.dailyExportEnabled) private var dailyExportEnabled
  @Default(.dailyExportHour) private var dailyExportHour
  @Default(.dailyExportMinute) private var dailyExportMinute

  @State private var viewModel = ViewModel()
  @State private var storageSize = ""
  @State private var exportStatus = ""

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 100_000
    return formatter
  }()

  private let hourRange = 0...23
  private let minuteRange = 0...59
  private let catchUpRange = 0...30

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $viewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
          Stepper("", value: $size, in: 1...100_000)
            .labelsHidden()
          Text(storageSize)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
            .onAppear {
              refreshStorageSize()
            }
        }
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("每日导出") }
      ) {
        Defaults.Toggle(key: .dailyExportEnabled) {
          Text("启用每日导出")
        }

        HStack {
          Text("导出时间")
          Stepper(value: $dailyExportHour, in: hourRange) {
            Text(String(format: "%02d", dailyExportHour))
              .monospacedDigit()
          }
          Text(":")
          Stepper(value: $dailyExportMinute, in: minuteRange) {
            Text(String(format: "%02d", dailyExportMinute))
              .monospacedDigit()
          }
        }
        .disabled(!dailyExportEnabled)

        HStack {
          Text("启动时补导出")
          Stepper(value: $dailyExportCatchUpDays, in: catchUpRange) {
            Text("\(dailyExportCatchUpDays) 天")
          }
        }
        .disabled(!dailyExportEnabled)

        Toggle("导出后清理孤儿资产", isOn: $dailyExportCleanupOrphans)
          .disabled(!dailyExportEnabled)

        HStack {
          Button("导出昨天") {
            exportStatus = "导出中..."
            DailyExportScheduler.shared.exportYesterday { outcome in
              exportStatus = exportMessage(outcome)
              refreshStorageSize()
            }
          }
          Button("导出今天") {
            exportStatus = "导出中..."
            DailyExportScheduler.shared.exportToday { outcome in
              exportStatus = exportMessage(outcome)
              refreshStorageSize()
            }
          }
          Button("打开导出目录") {
            openExportDirectory()
          }
        }

        Text(exportDirectoryPath)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)

        if !exportStatus.isEmpty {
          Text(exportStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func exportMessage(_ outcome: DailyExportOutcome) -> String {
    if let url = outcome.url {
      return "已导出：\(url.path)"
    }

    return "导出失败：\(outcome.errorMessage ?? "未知错误")"
  }

  private var exportDirectoryPath: String {
    ClipboardCoreStore.shared.exportDirectory.path
  }

  private func refreshStorageSize() {
    Task {
      let size = await Task.detached(priority: .utility) {
        ClipboardCoreStore.shared.storageSize
      }.value
      storageSize = size
    }
  }

  private func openExportDirectory() {
    do {
      let directory = try ClipboardCoreStore.shared.ensureExportDirectoryExists()
      NSWorkspace.shared.open(directory)
    } catch {
      exportStatus = "无法打开导出目录：\(error.localizedDescription)"
    }
  }

}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
