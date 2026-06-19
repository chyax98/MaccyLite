import AppKit

final class AppKitHistoryPanel: NSPanel, NSWindowDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
  private let searchField = NSSearchField()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let footerLabel = NSTextField(labelWithString: "")
  private let statusBarButton: NSStatusBarButton?
  private var items: [HistoryItemDecorator] = []
  private var searchTask: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
  private var lastReloadQuery: String?
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
    reload(query: searchField.stringValue, force: true)
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

  override func close() {
    debounceTask?.cancel()
    searchTask?.cancel()
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

  override func keyDown(with event: NSEvent) {
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

      let textField = NSTextField(labelWithString: "")
      textField.lineBreakMode = .byTruncatingTail
      textField.maximumNumberOfLines = 1
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell.textField = textField
      cell.addSubview(textField)

      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
      ])

      return cell
    }()

    let item = items[row]
    cell.textField?.stringValue = item.title.replacingOccurrences(of: "\n", with: " ").shortened(to: 300)
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateFooter()
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
    tableView.target = self
    tableView.doubleAction = #selector(doubleClickItem)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    footerLabel.textColor = .secondaryLabelColor
    footerLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    footerLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(searchField)
    container.addSubview(scrollView)
    container.addSubview(footerLabel)
    contentView = container

    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

      scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -6),

      footerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      footerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
      footerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
    ])
  }

  private func reload(query: String, force: Bool = false) {
    searchTask?.cancel()
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard force || trimmed != lastReloadQuery else {
      return
    }
    lastReloadQuery = trimmed

    searchTask = Task {
      let loaded = await Task.detached(priority: .userInitiated) {
        let listItems = trimmed.isEmpty
          ? ClipboardCoreStore.shared.latest(limit: 200)
          : ClipboardCoreStore.shared.search(trimmed, limit: 200)

        return listItems.map(HistoryItemDecorator.init)
      }.value

      guard !Task.isCancelled else { return }
      await MainActor.run {
        self.items = loaded
        self.tableView.reloadData()
        if !loaded.isEmpty {
          self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        self.updateFooter()
      }
    }
  }

  private func scheduleReload(query: String) {
    debounceTask?.cancel()
    let pendingQuery = query
    debounceTask = Task {
      try? await Task.sleep(nanoseconds: 120_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self.reload(query: pendingQuery)
      }
    }
  }

  private func selectedItem() -> HistoryItemDecorator? {
    guard items.indices.contains(tableView.selectedRow) else {
      return items.first
    }
    return items[tableView.selectedRow]
  }

  private func selectCurrentItem() {
    guard let item = selectedItem() else { return }
    History.shared.select(item)
  }

  private func deleteCurrentItem() {
    guard let item = selectedItem() else { return }
    History.shared.delete(item)
    reload(query: searchField.stringValue, force: true)
  }

  private func togglePinCurrentItem() {
    guard let item = selectedItem() else { return }
    History.shared.togglePin(item)
    reload(query: searchField.stringValue, force: true)
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

  @objc
  private func doubleClickItem() {
    selectCurrentItem()
  }
}
