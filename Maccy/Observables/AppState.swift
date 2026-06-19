import AppKit

final class AppState {
  static let shared = AppState()

  var appDelegate: AppDelegate?
  let popup = Popup()
  let history = History.shared

  private let about = About()
  private var preferencesWindowController: NSWindowController?

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() {
    if preferencesWindowController == nil {
      preferencesWindowController = NSWindowController(window: PreferencesWindow())
    }
    preferencesWindowController?.showWindow(nil)
    preferencesWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}

private final class PreferencesWindow: NSWindow {
  private let pasteByDefault = NSButton(checkboxWithTitle: "默认直接粘贴", target: nil, action: nil)
  private let removeFormatting = NSButton(checkboxWithTitle: "默认去除格式", target: nil, action: nil)
  private let dailyExport = NSButton(checkboxWithTitle: "启用每日导出", target: nil, action: nil)
  private let fileCapture = NSButton(checkboxWithTitle: "记录文件 URL", target: nil, action: nil)
  private let textCapture = NSButton(checkboxWithTitle: "记录文本/HTML/RTF", target: nil, action: nil)
  private let historySizeField = NSTextField()

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )

    title = "MaccyLite 设置"
    isReleasedWhenClosed = false
    center()
    configure()
    loadDefaults()
  }

  private func configure() {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(labelWithString: "核心设置")
    title.font = .boldSystemFont(ofSize: 16)

    let storageTitle = NSTextField(labelWithString: "记录类型")
    storageTitle.font = .boldSystemFont(ofSize: 13)

    let sizeRow = NSStackView()
    sizeRow.orientation = .horizontal
    sizeRow.spacing = 8
    sizeRow.addArrangedSubview(NSTextField(labelWithString: "历史上限"))
    historySizeField.frame.size.width = 90
    historySizeField.formatter = {
      let formatter = NumberFormatter()
      formatter.allowsFloats = false
      formatter.minimum = 100
      formatter.maximum = 100_000
      return formatter
    }()
    sizeRow.addArrangedSubview(historySizeField)

    [pasteByDefault, removeFormatting, dailyExport, fileCapture, textCapture].forEach {
      $0.target = self
      $0.action = #selector(saveDefaults)
    }
    historySizeField.target = self
    historySizeField.action = #selector(saveDefaults)

    stack.addArrangedSubview(title)
    stack.addArrangedSubview(pasteByDefault)
    stack.addArrangedSubview(removeFormatting)
    stack.addArrangedSubview(dailyExport)
    stack.addArrangedSubview(sizeRow)
    let separator = NSBox()
    separator.boxType = .separator
    stack.addArrangedSubview(separator)
    stack.addArrangedSubview(storageTitle)
    stack.addArrangedSubview(textCapture)
    stack.addArrangedSubview(fileCapture)

    let note = NSTextField(labelWithString: "已删除图片捕获、旧预览、多选连续粘贴、复杂外观设置。每日导出时间仍使用默认 00:05。")
    note.textColor = .secondaryLabelColor
    note.lineBreakMode = .byWordWrapping
    note.maximumNumberOfLines = 2
    stack.addArrangedSubview(note)

    contentView = NSView()
    contentView?.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 22)
    ])
  }

  private func loadDefaults() {
    pasteByDefault.state = AppPreferences.pasteByDefault ? .on : .off
    removeFormatting.state = AppPreferences.removeFormattingByDefault ? .on : .off
    dailyExport.state = AppPreferences.dailyExportEnabled ? .on : .off
    historySizeField.integerValue = AppPreferences.size

    let enabled = AppPreferences.enabledPasteboardTypes
    fileCapture.state = enabled.isDisjoint(with: StorageType.files.types) ? .off : .on
    textCapture.state = enabled.isDisjoint(with: StorageType.text.types) ? .off : .on
  }

  @objc
  private func saveDefaults() {
    AppPreferences.pasteByDefault = pasteByDefault.state == .on
    AppPreferences.removeFormattingByDefault = removeFormatting.state == .on
    AppPreferences.dailyExportEnabled = dailyExport.state == .on
    AppPreferences.size = max(100, historySizeField.integerValue)

    var enabled = Set<NSPasteboard.PasteboardType>()
    if fileCapture.state == .on {
      enabled.formUnion(StorageType.files.types)
    }
    if textCapture.state == .on {
      enabled.formUnion(StorageType.text.types)
    }
    AppPreferences.enabledPasteboardTypes = enabled
    DailyExportScheduler.shared.reschedule()
  }
}
