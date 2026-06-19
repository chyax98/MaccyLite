import AppKit.NSRunningApplication
import ClipboardCore
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings

@Observable
class History: ItemsContainer {
  static let shared = History()
  let logger = Logger(label: "com.local.MaccyLite")
  private struct MissingHistoryItemError: LocalizedError {
    var errorDescription: String? {
      "找不到历史条目"
    }
  }

  var items: [HistoryItemDecorator] = [] {
    didSet {
      rebuildItemCaches()
    }
  }
  var pasteStack: PasteStack?

  private(set) var pinnedItems: [HistoryItemDecorator] = []
  private(set) var unpinnedItems: [HistoryItemDecorator] = []
  private(set) var visiblePinnedItems: [HistoryItemDecorator] = []
  private(set) var visibleUnpinnedItems: [HistoryItemDecorator] = []
  private(set) var visibleItems: [HistoryItemDecorator] = []

  var firstVisibleItem: HistoryItemDecorator? {
    visibleItems.first
  }

  var lastVisibleItem: HistoryItemDecorator? {
    visibleItems.last
  }

  func firstVisibleItem(where predicate: (HistoryItemDecorator) -> Bool) -> HistoryItemDecorator? {
    visibleItems.first(where: predicate)
  }

  func lastVisibleItem(where predicate: (HistoryItemDecorator) -> Bool) -> HistoryItemDecorator? {
    visibleItems.last(where: predicate)
  }

  func visibleItem(before item: HistoryItemDecorator) -> HistoryItemDecorator? {
    visibleItems.item(before: item, where: { _ in true })
  }

  func visibleItem(after item: HistoryItemDecorator) -> HistoryItemDecorator? {
    visibleItems.item(after: item, where: { _ in true })
  }

  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        Task { @MainActor in
          await reloadVisibleItems()

          if searchQuery.isEmpty {
            AppState.shared.navigator.select(item: visibleUnpinnedItems.first)
          } else {
            AppState.shared.navigator.highlightFirst()
          }

          AppState.shared.popup.needsResize = true
        }
      }
    }
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return items.first { $0.shortcuts.contains(where: { $0.key == key }) }
  }

  private let throttler = Throttler(minimumDelay: 0.12)
  private let pageSize = 200
  private var reloadGeneration = 0

  init() {
    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await _ in Defaults.updates(.pinTo, initial: false) {
        try? await load()
      }
    }
  }

  @MainActor
  func load() async throws {
    await reloadVisibleItems()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  func add(_ item: ClipboardStoredItem) {
    let decorator = HistoryItemDecorator(item)
    items.removeAll { $0.itemID == item.id }
    items.insert(decorator, at: 0)
    limitVisibleHistorySize(to: Defaults[.size])
    updateShortcuts()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  func clear() {
    let itemIDs = unpinnedItems.map(\.itemID)
    items.removeAll(where: \.isUnpinned)
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    updateShortcuts()
    AppState.shared.popup.needsResize = true
    deleteItemsInBackground(itemIDs)
  }

  @MainActor
  func clearAll() {
    let itemIDs = items.map(\.itemID)
    items.removeAll()
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    AppState.shared.popup.needsResize = true
    deleteItemsInBackground(itemIDs)
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.cleanupImages()
    let itemID = item.itemID
    items.removeAll { $0 == item }

    updateShortcuts()
    AppState.shared.popup.needsResize = true
    deleteItemsInBackground([itemID])
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else {
      return
    }

    let modifierFlags = currentModifierFlags()

    if modifierFlags.isEmpty {
      guard !Defaults[.pasteByDefault] || Accessibility.check() else {
        return
      }
      AppState.shared.popup.close()
      copy(item, removeFormatting: Defaults[.removeFormattingByDefault], pasteAfter: Defaults[.pasteByDefault])
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        copy(item)
      case .paste:
        guard Accessibility.check() else {
          return
        }
        AppState.shared.popup.close()
        copy(item, pasteAfter: true)
      case .pasteWithoutFormatting:
        guard Accessibility.check() else {
          return
        }
        AppState.shared.popup.close()
        copy(item, removeFormatting: true, pasteAfter: true)
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>) {
    guard AppState.shared.multiSelectionEnabled else { return }
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let modifierFlags = currentModifierFlags()

    let stack = PasteStack(items: selection.items, modifierFlags: modifierFlags)
    pasteStack = stack

    logger.info("Initialising PasteStack with \(stack.items.count) items")
    logger.info("Copying \(item.title) from PasteStack")

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      copy(item, removeFormatting: Defaults[.removeFormattingByDefault])
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        copy(item)
      case .paste:
        AppState.shared.popup.close()
        copy(item)
      case .pasteWithoutFormatting:
        guard Accessibility.check() else {
          return
        }
        AppState.shared.popup.close()
        copy(item, removeFormatting: true, pasteAfter: true)
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  func handlePasteStack() {
    guard let stack = pasteStack else {
      return
    }

    guard let pasted = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("PasteStack pasted \(pasted.title)")

    stack.items.removeFirst()

    guard let item = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("Copying \(item.title) from PasteStack. \(stack.items.count) items remaining in stack.")

    Task { @MainActor in
      if stack.modifierFlags.isEmpty {
        copy(item, removeFormatting: Defaults[.removeFormattingByDefault])
      } else {
        switch HistoryItemAction(stack.modifierFlags) {
        case .copy, .paste:
          copy(item)
        case .pasteWithoutFormatting:
          copy(item, removeFormatting: true)
        case .unknown:
          return
        }
      }
    }
  }

  func interruptPasteStack() {
    guard pasteStack != nil else {
      return
    }
    logger.info("Interrupting PasteStack")
    pasteStack = nil
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.togglePin()
    sortPinned()

    searchQuery = ""
    updateShortcuts()
    if item.isUnpinned {
      AppState.shared.navigator.scrollTarget = item.id
    }
  }

  @MainActor
  private func reloadVisibleItems() async {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    reloadGeneration += 1
    let generation = reloadGeneration
    let pageSize = pageSize
    let storedItems = await Task.detached(priority: .userInitiated) {
      query.isEmpty
        ? ClipboardCoreStore.shared.latest(limit: pageSize)
        : ClipboardCoreStore.shared.search(query, limit: pageSize)
    }.value

    guard generation == reloadGeneration else {
      return
    }

    items = storedItems.map { storedItem in
      let decorator = HistoryItemDecorator(storedItem)
      decorator.highlight(query)
      return decorator
    }
    sortPinned()
    updateShortcuts()
  }

  @MainActor
  private func copy(
    _ item: HistoryItemDecorator,
    removeFormatting: Bool = false,
    pasteAfter: Bool = false
  ) {
    let itemID = item.itemID
    Task {
      let prepared = await Task.detached(priority: .userInitiated) {
        guard let storedItem = ClipboardCoreStore.shared.item(id: itemID) else {
          return Result<(String?, [(type: String, data: Data)]), Error>.failure(MissingHistoryItemError())
        }

        do {
          return .success((
            storedItem.sourceApp,
            try ClipboardCoreStore.shared.pasteboardPayload(for: storedItem, removeFormatting: removeFormatting)
          ))
        } catch {
          return .failure(error)
        }
      }.value

      switch prepared {
      case .success(let prepared):
        Clipboard.shared.copy(contents: prepared.1, sourceApp: prepared.0)
        if pasteAfter {
          Clipboard.shared.paste()
        }
      case .failure(let error):
        logger.warning("Failed to prepare clipboard payload for item \(itemID): \(error.localizedDescription)")
        AppState.shared.appDelegate?.showTransientStatus("复制失败")
        return
      }
    }
  }

  @MainActor
  private func limitVisibleHistorySize(to maxSize: Int) {
    let visibleUnpinnedLimit = min(maxSize, pageSize)
    var unpinnedCount = 0

    items = items.filter { item in
      guard item.isUnpinned else {
        return true
      }

      unpinnedCount += 1
      return unpinnedCount <= visibleUnpinnedLimit
    }
  }

  private func deleteItemsInBackground(_ itemIDs: [String]) {
    guard !itemIDs.isEmpty else {
      return
    }

    Task.detached(priority: .utility) {
      for itemID in itemIDs {
        ClipboardCoreStore.shared.delete(itemID: itemID)
      }
    }
  }

  private func currentModifierFlags() -> NSEvent.ModifierFlags {
    NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
  }

  private func sortPinned() {
    if Defaults[.pinTo] == .bottom {
      items.sort { lhs, rhs in
        if lhs.isPinned != rhs.isPinned {
          return lhs.isUnpinned && rhs.isPinned
        }
        return lhs.copiedAt > rhs.copiedAt
      }
    } else {
      items.sort { lhs, rhs in
        if lhs.isPinned != rhs.isPinned {
          return lhs.isPinned && rhs.isUnpinned
        }
        return lhs.copiedAt > rhs.copiedAt
      }
    }
    rebuildItemCaches()
  }

  private func updateShortcuts() {
    for item in pinnedItems {
      item.shortcuts = []
    }

    updateUnpinnedShortcuts()
  }

  private func updateUnpinnedShortcuts() {
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(9) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }

  private func rebuildItemCaches() {
    var pinnedItems: [HistoryItemDecorator] = []
    var unpinnedItems: [HistoryItemDecorator] = []
    var visiblePinnedItems: [HistoryItemDecorator] = []
    var visibleUnpinnedItems: [HistoryItemDecorator] = []
    var visibleItems: [HistoryItemDecorator] = []

    for item in items {
      if item.isPinned {
        pinnedItems.append(item)
        if item.isVisible {
          visiblePinnedItems.append(item)
          visibleItems.append(item)
        }
      } else {
        unpinnedItems.append(item)
        if item.isVisible {
          visibleUnpinnedItems.append(item)
          visibleItems.append(item)
        }
      }
    }

    self.pinnedItems = pinnedItems
    self.unpinnedItems = unpinnedItems
    self.visiblePinnedItems = visiblePinnedItems
    self.visibleUnpinnedItems = visibleUnpinnedItems
    self.visibleItems = visibleItems
  }
}
