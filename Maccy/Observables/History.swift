import AppKit.NSRunningApplication
import ClipboardCore
import Foundation
import Logging

class History {
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

  private(set) var pinnedItems: [HistoryItemDecorator] = []
  private(set) var unpinnedItems: [HistoryItemDecorator] = []
  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        Task { @MainActor in
          await reloadVisibleItems()
        }
      }
    }
  }

  private let throttler = Throttler(minimumDelay: 0.12)
  private let pageSize = 200
  private var reloadGeneration = 0

  init() {
  }

  @MainActor
  func load() async throws {
    await reloadVisibleItems()
  }

  @MainActor
  func add(_ item: ClipboardStoredItem) {
    let decorator = HistoryItemDecorator(item)
    items.removeAll { $0.itemID == item.id }
    items.insert(decorator, at: 0)
    limitVisibleHistorySize(to: AppPreferences.size)
  }

  @MainActor
  func clear() {
    let itemIDs = unpinnedItems.map(\.itemID)
    items.removeAll(where: \.isUnpinned)
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    deleteItemsInBackground(itemIDs)
  }

  @MainActor
  func clearAll() {
    let itemIDs = items.map(\.itemID)
    items.removeAll()
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    deleteItemsInBackground(itemIDs)
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    let itemID = item.itemID
    items.removeAll { $0 == item }

    deleteItemsInBackground([itemID])
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else {
      return
    }

    let modifierFlags = currentModifierFlags()

    if modifierFlags.isEmpty {
      guard !AppPreferences.pasteByDefault || Accessibility.check() else {
        return
      }
      AppState.shared.popup.close()
      copy(item, removeFormatting: AppPreferences.removeFormattingByDefault, pasteAfter: AppPreferences.pasteByDefault)
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
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.togglePin()
    sortPinned()

    searchQuery = ""
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

    items = storedItems.map(HistoryItemDecorator.init)
    sortPinned()
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
    if AppPreferences.pinTo == .bottom {
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

  private func rebuildItemCaches() {
    var pinnedItems: [HistoryItemDecorator] = []
    var unpinnedItems: [HistoryItemDecorator] = []

    for item in items {
      if item.isPinned {
        pinnedItems.append(item)
      } else {
        unpinnedItems.append(item)
      }
    }

    self.pinnedItems = pinnedItems
    self.unpinnedItems = unpinnedItems
  }
}
