import AppKit
import Carbon.HIToolbox

final class AppState {
  static let shared = AppState()

  var appDelegate: AppDelegate?
  let popup = Popup()
  let history = History.shared

  private let about = About()
  private var preferencesWindowController: NSWindowController?

  var menuIconText: String {
    history.menuIconText
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() {
    if preferencesWindowController == nil {
      preferencesWindowController = NSWindowController(window: PreferencesWindow())
    }
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindowController?.showWindow(nil)
    preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
  }

  func quit() {
    NSApp.terminate(self)
  }
}

private final class PreferencesWindow: NSWindow {
  private let pasteByDefault = NSButton(checkboxWithTitle: "选择历史后直接粘贴到当前 App", target: nil, action: nil)
  private let removeFormatting = NSButton(checkboxWithTitle: "粘贴时默认去除格式", target: nil, action: nil)
  private let dailyExport = NSButton(checkboxWithTitle: "每日自动导出剪贴板记录", target: nil, action: nil)
  private let fileCapture = NSButton(checkboxWithTitle: "记录文件 URL", target: nil, action: nil)
  private let textCapture = NSButton(checkboxWithTitle: "记录文本、HTML、RTF", target: nil, action: nil)
  private let historySizeField = NSTextField()
  private let hotKeyField = HotKeyRecorderField()
  private let accessibilityStatusLabel = NSTextField(labelWithString: "")
  private let exportDirectoryLabel = NSTextField(wrappingLabelWithString: "")

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
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

  override func becomeKey() {
    super.becomeKey()
    refreshAccessibilityStatus()
  }

  private func configure() {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false

    let sizeRow = NSStackView()
    sizeRow.orientation = .horizontal
    sizeRow.spacing = 8
    sizeRow.alignment = .centerY
    sizeRow.addArrangedSubview(NSTextField(labelWithString: "最多保留"))
    historySizeField.frame.size.width = 90
    historySizeField.formatter = {
      let formatter = NumberFormatter()
      formatter.allowsFloats = false
      formatter.minimum = 100
      formatter.maximum = 100_000
      return formatter
    }()
    sizeRow.addArrangedSubview(historySizeField)
    sizeRow.addArrangedSubview(NSTextField(labelWithString: "条历史"))

    [pasteByDefault, removeFormatting, dailyExport, fileCapture, textCapture].forEach {
      $0.target = self
      $0.action = #selector(saveDefaults)
    }
    historySizeField.target = self
    historySizeField.action = #selector(saveDefaults)
    hotKeyField.onChange = { keyCode, modifiers in
      AppPreferences.popupHotKeyKeyCode = keyCode
      AppPreferences.popupHotKeyModifiers = modifiers
      if !HotKeyManager.shared.start() {
        NSSound.beep()
      }
    }

    stack.addArrangedSubview(sectionTitle("核心设置"))
    addSetting(
      hotKeyField,
      "点击输入框后按新的组合键。默认是 ⌥C，用来打开或关闭剪贴板历史面板。",
      to: stack
    )
    addSetting(
      pasteByDefault,
      "关闭时按 Enter 只复制到剪贴板；开启后会自动粘贴到当前正在使用的 App，需要系统辅助功能权限。",
      to: stack
    )
    let accessibilityRow = NSStackView()
    accessibilityRow.orientation = .horizontal
    accessibilityRow.spacing = 8
    accessibilityRow.alignment = .centerY
    accessibilityStatusLabel.textColor = .secondaryLabelColor
    accessibilityRow.addArrangedSubview(accessibilityStatusLabel)
    accessibilityRow.addArrangedSubview(NSButton(title: "打开辅助功能设置", target: self, action: #selector(openAccessibilitySettings)))
    stack.addArrangedSubview(accessibilityRow)
    addSetting(
      removeFormatting,
      "开启后默认只写入纯文本，适合从网页或富文本编辑器复制内容后粘贴到对话框。",
      to: stack
    )
    addSetting(
      dailyExport,
      "开启后每天 00:05 导出昨天的剪贴板记录；启动时会补导最近缺失的日期。",
      to: stack
    )
    addSetting(
      sizeRow,
      "超过上限后会优先清理未 Pin 的旧记录。Pin 的记录会保留。",
      to: stack
    )

    stack.addArrangedSubview(separator())
    stack.addArrangedSubview(sectionTitle("记录类型"))
    addSetting(
      textCapture,
      "记录普通文本、网页 HTML 和 RTF。大文本内部可能存为资产文件，但粘贴时会还原为原始文本。",
      to: stack
    )
    addSetting(
      fileCapture,
      "记录文件的 file URL，不复制文件本体。选中时使用系统缩略图或文件图标预览。",
      to: stack
    )
    stack.addArrangedSubview(description("图片会始终记录，并只在列表选中时加载预览，避免历史列表批量解码图片。"))

    stack.addArrangedSubview(separator())
    stack.addArrangedSubview(sectionTitle("每日导出"))
    stack.addArrangedSubview(description("格式：Markdown（.md）。每条记录包含时间、来源 App、类型、复制次数、文本内容、文件 URL、图片尺寸和资产路径。"))
    exportDirectoryLabel.textColor = .secondaryLabelColor
    exportDirectoryLabel.font = .systemFont(ofSize: 12)
    exportDirectoryLabel.maximumNumberOfLines = 3
    stack.addArrangedSubview(exportDirectoryLabel)

    let exportRow = NSStackView()
    exportRow.orientation = .horizontal
    exportRow.spacing = 8
    let openExportFolder = NSButton(title: "打开导出文件夹", target: self, action: #selector(openExportDirectory))
    let chooseExportFolder = NSButton(title: "选择导出文件夹…", target: self, action: #selector(chooseExportDirectory))
    let resetExportFolder = NSButton(title: "恢复默认路径", target: self, action: #selector(resetExportDirectory))
    exportRow.addArrangedSubview(openExportFolder)
    exportRow.addArrangedSubview(chooseExportFolder)
    exportRow.addArrangedSubview(resetExportFolder)
    stack.addArrangedSubview(exportRow)

    contentView = NSView()
    contentView?.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView!.bottomAnchor, constant: -22)
    ])
  }

  private func loadDefaults() {
    pasteByDefault.state = AppPreferences.pasteByDefault ? .on : .off
    removeFormatting.state = AppPreferences.removeFormattingByDefault ? .on : .off
    dailyExport.state = AppPreferences.dailyExportEnabled ? .on : .off
    historySizeField.integerValue = AppPreferences.size
    hotKeyField.setHotKey(
      keyCode: AppPreferences.popupHotKeyKeyCode,
      modifiers: AppPreferences.popupHotKeyModifiers
    )

    let enabled = AppPreferences.enabledPasteboardTypes
    fileCapture.state = enabled.isDisjoint(with: StorageType.files.types) ? .off : .on
    textCapture.state = enabled.isDisjoint(with: StorageType.text.types) ? .off : .on
    refreshAccessibilityStatus()
    refreshExportDirectoryLabel()
  }

  @objc
  private func saveDefaults() {
    AppPreferences.pasteByDefault = pasteByDefault.state == .on
    AppPreferences.removeFormattingByDefault = removeFormatting.state == .on
    AppPreferences.dailyExportEnabled = dailyExport.state == .on
    AppPreferences.size = max(100, historySizeField.integerValue)

    var enabled = Set(StorageType.images.types)
    if fileCapture.state == .on {
      enabled.formUnion(StorageType.files.types)
    }
    if textCapture.state == .on {
      enabled.formUnion(StorageType.text.types)
    }
    AppPreferences.enabledPasteboardTypes = enabled
    DailyExportScheduler.shared.reschedule()
  }

  @objc
  private func openExportDirectory() {
    do {
      let directory = try ClipboardCoreStore.shared.ensureExportDirectoryExists()
      NSWorkspace.shared.open(directory)
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  @objc
  private func chooseExportDirectory() {
    let panel = NSOpenPanel()
    panel.title = "选择每日导出文件夹"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = ClipboardCoreStore.shared.exportDirectory

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    AppPreferences.dailyExportDirectoryPath = url.path
    refreshExportDirectoryLabel()
    DailyExportScheduler.shared.reschedule()
  }

  @objc
  private func resetExportDirectory() {
    AppPreferences.dailyExportDirectoryPath = nil
    refreshExportDirectoryLabel()
    DailyExportScheduler.shared.reschedule()
  }

  @objc
  private func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  private func refreshAccessibilityStatus() {
    accessibilityStatusLabel.stringValue = Accessibility.allowed
      ? "辅助功能：已对当前版本生效"
      : "辅助功能：未对当前版本生效"
  }

  private func refreshExportDirectoryLabel() {
    let path = ClipboardCoreStore.shared.exportDirectory.path
    let suffix = AppPreferences.dailyExportDirectoryPath == nil ? "（默认）" : "（自定义）"
    exportDirectoryLabel.stringValue = "路径：\(path) \(suffix)"
  }

  private func addSetting(_ control: NSView, _ help: String, to stack: NSStackView) {
    stack.addArrangedSubview(control)
    stack.addArrangedSubview(description(help))
  }

  private func sectionTitle(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .boldSystemFont(ofSize: 15)
    return label
  }

  private func description(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: 12)
    label.maximumNumberOfLines = 3
    return label
  }

  private func separator() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    return separator
  }
}

private final class HotKeyRecorderField: NSTextField {
  var onChange: ((UInt32, UInt32) -> Void)?
  private var keyCode: UInt32 = UInt32(kVK_ANSI_C)
  private var modifiers: UInt32 = UInt32(optionKey)
  private var keyMonitor: Any?
  private var isRecording = false

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
    isEditable = false
    isSelectable = false
    isBezeled = true
    drawsBackground = true
    alignment = .center
    focusRingType = .default
    font = .monospacedSystemFont(ofSize: 13, weight: .medium)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  deinit {
    stopRecording()
  }

  override func becomeFirstResponder() -> Bool {
    startRecording()
    return true
  }

  override func resignFirstResponder() -> Bool {
    stopRecording()
    return true
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    startRecording()
  }

  override func keyDown(with event: NSEvent) {
    record(event)
  }

  func setHotKey(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    stringValue = "\(Self.modifierDescription(modifiers))\(Self.keyName(Int(keyCode)))"
  }

  private func startRecording() {
    guard !isRecording else {
      return
    }

    isRecording = true
    HotKeyManager.shared.stop()
    stringValue = "按新的快捷键"
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window?.firstResponder === self else {
        return event
      }

      self.record(event)
      return nil
    }
  }

  private func stopRecording() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
    isRecording = false
    stringValue = "\(Self.modifierDescription(modifiers))\(Self.keyName(Int(keyCode)))"
    if !HotKeyManager.shared.start() {
      NSSound.beep()
    }
  }

  private func record(_ event: NSEvent) {
    let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
    guard carbonModifiers != 0, !Self.modifierOnlyKeyCodes.contains(Int(event.keyCode)) else {
      NSSound.beep()
      return
    }

    setHotKey(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
    onChange?(keyCode, modifiers)
    window?.makeFirstResponder(nil)
  }

  private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }
    return modifiers
  }

  private static func modifierDescription(_ modifiers: UInt32) -> String {
    var description = ""
    if modifiers & UInt32(controlKey) != 0 {
      description += "⌃"
    }
    if modifiers & UInt32(optionKey) != 0 {
      description += "⌥"
    }
    if modifiers & UInt32(shiftKey) != 0 {
      description += "⇧"
    }
    if modifiers & UInt32(cmdKey) != 0 {
      description += "⌘"
    }
    return description
  }

  private static func keyName(_ keyCode: Int) -> String {
    keyNames[keyCode] ?? "Key \(keyCode)"
  }

  private static let modifierOnlyKeyCodes: Set<Int> = Set([
    Int(kVK_Command),
    Int(kVK_RightCommand),
    Int(kVK_Shift),
    Int(kVK_RightShift),
    Int(kVK_Option),
    Int(kVK_RightOption),
    Int(kVK_Control),
    Int(kVK_RightControl),
    Int(kVK_Function)
  ])

  private static let keyNames: [Int: String] = [
    kVK_ANSI_A: "A",
    kVK_ANSI_B: "B",
    kVK_ANSI_C: "C",
    kVK_ANSI_D: "D",
    kVK_ANSI_E: "E",
    kVK_ANSI_F: "F",
    kVK_ANSI_G: "G",
    kVK_ANSI_H: "H",
    kVK_ANSI_I: "I",
    kVK_ANSI_J: "J",
    kVK_ANSI_K: "K",
    kVK_ANSI_L: "L",
    kVK_ANSI_M: "M",
    kVK_ANSI_N: "N",
    kVK_ANSI_O: "O",
    kVK_ANSI_P: "P",
    kVK_ANSI_Q: "Q",
    kVK_ANSI_R: "R",
    kVK_ANSI_S: "S",
    kVK_ANSI_T: "T",
    kVK_ANSI_U: "U",
    kVK_ANSI_V: "V",
    kVK_ANSI_W: "W",
    kVK_ANSI_X: "X",
    kVK_ANSI_Y: "Y",
    kVK_ANSI_Z: "Z",
    kVK_ANSI_0: "0",
    kVK_ANSI_1: "1",
    kVK_ANSI_2: "2",
    kVK_ANSI_3: "3",
    kVK_ANSI_4: "4",
    kVK_ANSI_5: "5",
    kVK_ANSI_6: "6",
    kVK_ANSI_7: "7",
    kVK_ANSI_8: "8",
    kVK_ANSI_9: "9",
    kVK_Space: "Space",
    kVK_Return: "Return",
    kVK_Tab: "Tab",
    kVK_Escape: "Esc",
    kVK_Delete: "Delete",
    kVK_ForwardDelete: "Forward Delete",
    kVK_LeftArrow: "←",
    kVK_RightArrow: "→",
    kVK_UpArrow: "↑",
    kVK_DownArrow: "↓"
  ].reduce(into: [Int: String]()) { result, entry in
    result[Int(entry.key)] = entry.value
  }
}
