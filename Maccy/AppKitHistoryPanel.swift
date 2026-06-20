import AppKit
import ClipboardCore

final class AppKitHistoryPanel: NSPanel, NSWindowDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
  private let searchField = NSSearchField()
  private let tableView = HistoryTableView()
  private let scrollView = NSScrollView()
  private let previewContainer = NSView()
  private let previewStack = NSStackView()
  private let previewImageView = NSImageView()
  private let previewTextScrollView = NSScrollView()
  private let previewTextView = NSTextView()
  private let previewLabel = NSTextField(labelWithString: "")
  private let footerLabel = NSTextField(labelWithString: "")
  private let statusBarButton: NSStatusBarButton?
  private var items: [ClipboardListItem] = []
  private var itemTitles: [String] = []
  private var searchTask: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?
  private let reloadQueue = DispatchQueue(label: "com.local.MaccyLite.history-panel.reload", qos: .userInitiated)
  private var reloadRequestID = 0
  private var previewRequestID = 0
  private var lastReloadQuery: String?
  private var lastLoadedRevision = -1
  private var isPresented = false

  init(
    contentRect: NSRect,
    identifier: String,
    statusBarButton: NSStatusBarButton?
  ) {
    self.statusBarButton = statusBarButton

    super.init(
      contentRect: contentRect,
      styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    self.identifier = NSUserInterfaceItemIdentifier(identifier)
    delegate = self
    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    titlebarSeparatorStyle = .none
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    backgroundColor = .windowBackgroundColor

    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    configureContent()
  }

  func toggle(height: CGFloat, at popupPosition: PopupPosition = AppPreferences.popupPosition) {
    isPresented ? close() : open(height: height, at: popupPosition)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = AppPreferences.popupPosition) {
    let size = AppPreferences.windowSize
    setContentSize(NSSize(width: size.width, height: size.height))
    setFrameOrigin(popupPosition.origin(size: frame.size, statusBarButton: statusBarButton))
    searchField.stringValue = ""
    reload(query: "", force: true)
    orderFrontRegardless()
    makeKey()
    makeFirstResponder(searchField)
    isPresented = true

    if popupPosition == .statusItem {
      statusBarButton?.isHighlighted = true
    }
  }

  func verticallyResize(to newHeight: CGFloat) {
    var newFrame = frame
    newFrame.origin.y += frame.height - newHeight
    newFrame.size.height = newHeight
    setFrame(newFrame, display: true)
  }

  func isOpen() -> Bool {
    isPresented
  }

  func refreshIfOpen() {
    guard isPresented else {
      return
    }
    reload(query: searchField.stringValue, force: true)
  }

  override func close() {
    debounceTask?.cancel()
    searchTask?.cancel()
    previewTask?.cancel()
    super.close()
    isPresented = false
    statusBarButton?.isHighlighted = false
    AppState.shared.popup.reset()
  }

  override func resignKey() {
    super.resignKey()
    if NSApp.alertWindow == nil {
      close()
    }
  }

  override var canBecomeKey: Bool {
    true
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    guard modifierFlags == .command,
          let key = event.charactersIgnoringModifiers?.lowercased() else {
      return super.performKeyEquivalent(with: event)
    }

    switch key {
    case "a":
      if routeTextCommand(#selector(NSResponder.selectAll(_:)), allowPreviewText: true) {
        return true
      }
    case "c":
      if routeTextCommand(#selector(NSText.copy(_:)), allowPreviewText: true) {
        return true
      }
    case "v":
      if routeTextCommand(#selector(NSText.paste(_:)), allowPreviewText: false) {
        return true
      }
    case "x":
      if routeTextCommand(#selector(NSText.cut(_:)), allowPreviewText: false) {
        return true
      }
    default:
      break
    }

    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if isPreviewTextFocused {
      if event.keyCode == 53 {
        close()
      } else {
        super.keyDown(with: event)
      }
      return
    }

    if isSearchFieldEditing, !shouldHandleSearchFieldKey(event) {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 36, 76:
      selectCurrentItem()
    case 35 where event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option):
      togglePinCurrentItem()
    case 53:
      close()
    case 125:
      moveSelection(by: 1)
    case 126:
      moveSelection(by: -1)
    case 51:
      deleteCurrentItem()
    default:
      super.keyDown(with: event)
    }
  }

  private var isSearchFieldEditing: Bool {
    guard let firstResponder else {
      return false
    }

    return firstResponder === searchField.currentEditor()
  }

  private var isPreviewTextFocused: Bool {
    firstResponder === previewTextView
  }

  private func shouldHandleSearchFieldKey(_ event: NSEvent) -> Bool {
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    guard modifierFlags.isEmpty else {
      return false
    }

    return [36, 53, 76, 125, 126].contains(Int(event.keyCode))
  }

  private func routeTextCommand(_ action: Selector, allowPreviewText: Bool) -> Bool {
    if isSearchFieldEditing, let editor = searchField.currentEditor() {
      return NSApp.sendAction(action, to: editor, from: self)
    }

    if allowPreviewText, isPreviewTextFocused {
      return NSApp.sendAction(action, to: previewTextView, from: self)
    }

    return false
  }

  func controlTextDidChange(_ notification: Notification) {
    scheduleReload(query: searchField.stringValue)
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    items.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    34
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard items.indices.contains(row) else {
      return nil
    }

    let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
      let cell = NSTableCellView()
      cell.identifier = identifier

      let imageView = NSImageView()
      imageView.imageScaling = .scaleProportionallyDown
      imageView.translatesAutoresizingMaskIntoConstraints = false
      cell.imageView = imageView
      cell.addSubview(imageView)

      let textField = NSTextField(labelWithString: "")
      textField.lineBreakMode = .byTruncatingTail
      textField.maximumNumberOfLines = 1
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell.textField = textField
      cell.addSubview(textField)

      NSLayoutConstraint.activate([
        imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
        imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        imageView.widthAnchor.constraint(equalToConstant: 18),
        imageView.heightAnchor.constraint(equalToConstant: 18),
        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
      ])

      return cell
    }()

    cell.textField?.stringValue = itemTitles.indices.contains(row) ? itemTitles[row] : Self.titleText(for: items[row])
    cell.imageView?.image = Self.icon(for: items[row])
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateFooter()
    updatePreview()
  }

  private func configureContent() {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    searchField.placeholderString = "搜索剪贴板历史"
    searchField.delegate = self
    searchField.translatesAutoresizingMaskIntoConstraints = false

    tableView.headerView = nil
    tableView.rowSizeStyle = .custom
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.selectionHighlightStyle = .regular
    tableView.delegate = self
    tableView.dataSource = self
    tableView.onDoubleClickRow = { [weak self] row in
      self?.pasteItem(at: row)
    }

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.wantsLayer = true
    previewContainer.layer?.borderColor = NSColor.separatorColor.cgColor
    previewContainer.layer?.borderWidth = 1

    previewImageView.imageScaling = .scaleProportionallyUpOrDown
    previewImageView.translatesAutoresizingMaskIntoConstraints = false
    previewImageView.isHidden = true

    previewTextView.isEditable = false
    previewTextView.isSelectable = true
    previewTextView.drawsBackground = false
    previewTextView.textColor = .labelColor
    previewTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    previewTextView.textContainerInset = NSSize(width: 12, height: 12)
    previewTextView.isHorizontallyResizable = false
    previewTextView.isVerticallyResizable = true
    previewTextView.minSize = NSSize(width: 0, height: 0)
    previewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    previewTextView.autoresizingMask = [.width]
    previewTextView.textContainer?.widthTracksTextView = true
    previewTextView.textContainer?.containerSize = NSSize(
      width: previewTextScrollView.contentSize.width,
      height: CGFloat.greatestFiniteMagnitude
    )
    previewTextView.frame = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))
    previewTextView.translatesAutoresizingMaskIntoConstraints = true

    previewTextScrollView.documentView = previewTextView
    previewTextScrollView.hasVerticalScroller = true
    previewTextScrollView.drawsBackground = false
    previewTextScrollView.translatesAutoresizingMaskIntoConstraints = false
    previewTextScrollView.isHidden = true

    previewLabel.textColor = .secondaryLabelColor
    previewLabel.lineBreakMode = .byCharWrapping
    previewLabel.maximumNumberOfLines = 12
    previewLabel.usesSingleLineMode = false
    previewLabel.cell?.wraps = true
    previewLabel.cell?.isScrollable = false
    previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    previewLabel.translatesAutoresizingMaskIntoConstraints = false

    previewStack.orientation = .vertical
    previewStack.alignment = .centerX
    previewStack.spacing = 8
    previewStack.translatesAutoresizingMaskIntoConstraints = false
    previewStack.addArrangedSubview(previewImageView)
    previewStack.addArrangedSubview(previewTextScrollView)
    previewStack.addArrangedSubview(previewLabel)
    previewContainer.addSubview(previewStack)

    footerLabel.textColor = .secondaryLabelColor
    footerLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    footerLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(searchField)
    container.addSubview(scrollView)
    container.addSubview(previewContainer)
    container.addSubview(footerLabel)
    contentView = container

    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

      scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      scrollView.widthAnchor.constraint(equalToConstant: 330),
      scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -6),

      previewContainer.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
      previewContainer.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 10),
      previewContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
      previewContainer.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -6),

      previewStack.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 10),
      previewStack.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -10),
      previewStack.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 10),
      previewStack.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -10),

      previewImageView.widthAnchor.constraint(lessThanOrEqualTo: previewContainer.widthAnchor, constant: -20),
      previewImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 320),
      previewTextScrollView.widthAnchor.constraint(equalTo: previewStack.widthAnchor),
      previewTextScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
      previewLabel.widthAnchor.constraint(equalTo: previewStack.widthAnchor),

      footerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      footerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
      footerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
    ])
  }

  private func reload(query: String, force: Bool = false) {
    searchTask?.cancel()
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let revision = ClipboardCoreStore.shared.revision
    guard force || trimmed != lastReloadQuery || revision != lastLoadedRevision else {
      return
    }
    lastReloadQuery = trimmed
    reloadRequestID += 1
    let requestID = reloadRequestID

    searchTask = Task {
      let loaded = await withCheckedContinuation { continuation in
        reloadQueue.async {
          guard requestID == self.reloadRequestID else {
            continuation.resume(returning: (items: [ClipboardListItem](), titles: [String]()))
            return
          }

          let listItems = trimmed.isEmpty
            ? ClipboardCoreStore.shared.latest(limit: 200)
            : ClipboardCoreStore.shared.search(trimmed, limit: 200)

          continuation.resume(returning: (items: listItems, titles: listItems.map(Self.titleText(for:))))
        }
      }

      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard requestID == self.reloadRequestID,
              trimmed == self.lastReloadQuery else {
          return
        }

        guard revision == ClipboardCoreStore.shared.revision else {
          self.reload(query: trimmed, force: true)
          return
        }

        self.items = loaded.items
        self.itemTitles = loaded.titles
        self.tableView.reloadData()
        if !loaded.items.isEmpty {
          self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        self.lastLoadedRevision = revision
        self.updateFooter()
        self.updatePreview()
      }
    }
  }

  private func scheduleReload(query: String) {
    debounceTask?.cancel()
    let pendingQuery = query
    debounceTask = Task {
      try? await Task.sleep(nanoseconds: Self.searchDebounceNanoseconds)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self.reload(query: pendingQuery)
      }
    }
  }

  private func selectedItem() -> ClipboardListItem? {
    guard let row = selectedRow() else {
      return items.first
    }
    return items[row]
  }

  private func selectedRow() -> Int? {
    guard items.indices.contains(tableView.selectedRow) else {
      return nil
    }
    return tableView.selectedRow
  }

  private func selectCurrentItem() {
    guard let item = selectedItem() else { return }
    History.shared.select(item)
  }

  private func pasteItem(at row: Int) {
    guard items.indices.contains(row) else {
      return
    }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    History.shared.paste(items[row])
  }

  private func deleteCurrentItem() {
    guard let item = selectedItem() else { return }
    let selectedRow = tableView.selectedRow
    History.shared.delete(item)
    if let row = items.firstIndex(where: { $0.id == item.id }) {
      items.remove(at: row)
      if itemTitles.indices.contains(row) {
        itemTitles.remove(at: row)
      }
    }
    tableView.reloadData()
    if !items.isEmpty {
      tableView.selectRowIndexes(IndexSet(integer: min(max(selectedRow, 0), items.count - 1)), byExtendingSelection: false)
    }
    updateFooter()
    updatePreview()
  }

  private func togglePinCurrentItem() {
    guard let row = selectedRow() else { return }
    items[row].isPinned.toggle()
    let item = items[row]
    Task.detached(priority: .utility) {
      ClipboardCoreStore.shared.setPinned(item.isPinned, itemID: item.id)
    }
    sortLocalItems()
    tableView.reloadData()
    if let row = items.firstIndex(where: { $0.id == item.id }) {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      tableView.scrollRowToVisible(row)
    }
    updateFooter()
    updatePreview()
  }

  private func moveSelection(by delta: Int) {
    guard !items.isEmpty else { return }
    let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
    let next = min(max(current + delta, 0), items.count - 1)
    tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
    tableView.scrollRowToVisible(next)
  }

  private func updateFooter() {
    if let item = selectedItem() {
      let action = AppPreferences.pasteByDefault ? "粘贴" : "复制"
      footerLabel.stringValue = "Enter \(action) · Option+P Pin · Delete 删除 · \(item.copiedAt.formatted(date: .numeric, time: .shortened))"
    } else {
      footerLabel.stringValue = "没有历史记录"
    }
  }

  private func updatePreview() {
    previewTask?.cancel()
    previewRequestID += 1
    let requestID = previewRequestID

    guard let item = selectedItem() else {
      showPreviewText("没有可预览内容")
      return
    }

    if item.primaryType == ClipboardContentType.fileURL {
      showPreviewText("正在载入文件预览...")
      let scale = NSScreen.main?.backingScaleFactor ?? 2
      previewTask = Task.detached(priority: .utility) {
        let payload = await HistoryPreviewRenderer.loadFilePreview(itemID: item.id, scale: scale)
        await MainActor.run {
          guard requestID == self.previewRequestID else { return }
          let text = payload.text
          if let image = payload.image {
            self.showPreviewImage(image, text: "\(text)\n\n\(HistoryPreviewRenderer.infoText(for: item))")
          } else {
            self.showPreviewText("\(text)\n\n\(HistoryPreviewRenderer.infoText(for: item))")
          }
        }
      }
      return
    }

    if item.hasImage {
      showPreviewText("正在载入图片...")
      previewTask = Task.detached(priority: .utility) {
        let image = HistoryPreviewRenderer.loadPreviewImage(itemID: item.id)
        await MainActor.run {
          guard requestID == self.previewRequestID else { return }
          if let image {
            self.showPreviewImage(image, text: HistoryPreviewRenderer.infoText(for: item))
          } else {
            self.showPreviewText("图片预览不可用")
          }
        }
      }
      return
    }

    showPreviewText("正在载入文本...")
    previewTask = Task.detached(priority: .utility) {
      let preview = HistoryPreviewRenderer.loadTextPreview(itemID: item.id, fallback: item.displayText)
      await MainActor.run {
        guard requestID == self.previewRequestID else { return }
        self.showPreviewTextDocument(
          HistoryPreviewRenderer.previewText(preview),
          info: HistoryPreviewRenderer.infoText(for: item, characterCount: preview.characterCount)
        )
      }
    }
  }

  private func showPreviewImage(_ image: NSImage, text: String? = nil) {
    previewTextScrollView.isHidden = true
    previewLabel.stringValue = text ?? ""
    previewLabel.isHidden = text == nil
    previewImageView.image = image
    previewImageView.isHidden = false
  }

  private func showPreviewText(_ text: String) {
    previewImageView.image = nil
    previewImageView.isHidden = true
    previewTextScrollView.isHidden = true
    previewLabel.stringValue = text
    previewLabel.isHidden = false
  }

  private func showPreviewTextDocument(_ text: String, info: String) {
    previewImageView.image = nil
    previewImageView.isHidden = true
    previewLabel.stringValue = info
    previewLabel.isHidden = false
    previewTextScrollView.isHidden = false
    contentView?.layoutSubtreeIfNeeded()
    let textWidth = max(previewTextScrollView.contentSize.width, 240)
    previewTextView.frame = NSRect(
      origin: .zero,
      size: NSSize(width: textWidth, height: max(previewTextScrollView.contentSize.height, 260))
    )
    previewTextView.textContainer?.containerSize = NSSize(
      width: textWidth,
      height: CGFloat.greatestFiniteMagnitude
    )
    previewTextView.string = text
    if let layoutManager = previewTextView.layoutManager,
       let textContainer = previewTextView.textContainer {
      layoutManager.ensureLayout(for: textContainer)
      let usedHeight = layoutManager.usedRect(for: textContainer).height
      let insetHeight = previewTextView.textContainerInset.height * 2
      let documentHeight = max(
        previewTextScrollView.contentSize.height,
        ceil(usedHeight + insetHeight + 16)
      )
      previewTextView.setFrameSize(NSSize(width: textWidth, height: documentHeight))
    }
    previewTextView.scrollToBeginningOfDocument(nil)
  }

  private func sortLocalItems() {
    items.sort { lhs, rhs in
      if lhs.isPinned != rhs.isPinned {
        return AppPreferences.pinTo == .bottom ? !lhs.isPinned && rhs.isPinned : lhs.isPinned && !rhs.isPinned
      }
      return lhs.copiedAt > rhs.copiedAt
    }
    itemTitles = items.map(Self.titleText(for:))
  }

  nonisolated private static func titleText(for item: ClipboardListItem) -> String {
    let text = item.displayText.replacingOccurrences(of: "\n", with: " ")
    if item.primaryType == ClipboardContentType.fileURL {
      return HistoryPreviewRenderer.filePreviewText(item.displayText).shortened(to: 120)
    }
    if item.hasImage {
      return text == "图片" ? "图片" : text.shortened(to: 120)
    }
    return text.shortened(to: 160)
  }

  nonisolated private static func icon(for item: ClipboardListItem) -> NSImage? {
    if item.primaryType == ClipboardContentType.fileURL {
      return NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
    }
    if item.hasImage {
      return NSImage(systemSymbolName: "photo", accessibilityDescription: "图片")
    }
    if item.isPinned {
      return NSImage(systemSymbolName: "pin", accessibilityDescription: "固定")
    }
    return NSImage(systemSymbolName: "doc.text", accessibilityDescription: "文本")
  }

  nonisolated private static let searchDebounceNanoseconds: UInt64 = 250_000_000

}

private final class HistoryTableView: NSTableView {
  var onDoubleClickRow: ((Int) -> Void)?

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let clickedRow = row(at: point)

    super.mouseDown(with: event)

    guard event.clickCount == 2, clickedRow >= 0 else {
      return
    }

    DispatchQueue.main.async { [weak self] in
      self?.onDoubleClickRow?(clickedRow)
    }
  }
}
