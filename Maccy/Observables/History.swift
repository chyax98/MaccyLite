import AppKit.NSRunningApplication
import ClipboardCore
import Foundation
import Logging

class History {
  static let shared = History()
  let logger = Logger(label: "com.local.MaccyLite")
  private let menuTextLock = NSLock()
  private var cachedMenuText: String?

  private struct MissingHistoryItemError: LocalizedError {
    var errorDescription: String? {
      "找不到历史条目"
    }
  }

  init() {
  }

  var menuIconText: String {
    let title = cachedLatestMenuText()
      .shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return title.replacingOccurrences(of: "\n", with: " ").shortened(to: 20)
  }

  @MainActor
  func add(_ item: ClipboardStoredItem) {
    updateMenuText(item.isPinned ? nil : item.displayText)
  }

  @MainActor
  func clear() {
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    updateMenuText(nil)
    Task.detached(priority: .utility) {
      ClipboardCoreStore.shared.deleteUnpinned()
    }
  }

  @MainActor
  func clearAll() {
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    updateMenuText(nil)
    Task.detached(priority: .utility) {
      ClipboardCoreStore.shared.deleteAll()
    }
  }

  @MainActor
  func delete(_ item: ClipboardListItem?) {
    guard let item else { return }

    let itemID = item.id
    Task.detached(priority: .utility) {
      ClipboardCoreStore.shared.delete(itemID: itemID)
      let latest = ClipboardCoreStore.shared.latestUnpinnedDisplayText()
      self.updateMenuText(latest)
      await MainActor.run {
        AppState.shared.appDelegate?.refreshMenuIconText()
      }
    }
  }

  @MainActor
  func select(_ item: ClipboardListItem?) {
    guard let item else {
      return
    }

    let modifierFlags = currentModifierFlags()

    if modifierFlags.isEmpty {
      guard !AppPreferences.pasteByDefault || checkAccessibilityForPaste() else {
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
        guard checkAccessibilityForPaste() else {
          return
        }
        AppState.shared.popup.close()
        copy(item, pasteAfter: true)
      case .pasteWithoutFormatting:
        guard checkAccessibilityForPaste() else {
          return
        }
        AppState.shared.popup.close()
        copy(item, removeFormatting: true, pasteAfter: true)
      case .unknown:
        return
      }
    }
  }

  @MainActor
  func paste(_ item: ClipboardListItem?) {
    guard let item else {
      return
    }
    guard checkAccessibilityForPaste() else {
      return
    }

    AppState.shared.popup.close()
    copy(item, removeFormatting: AppPreferences.removeFormattingByDefault, pasteAfter: true)
  }

  @MainActor
  private func copy(
    _ item: ClipboardListItem,
    removeFormatting: Bool = false,
    pasteAfter: Bool = false
  ) {
    let itemID = item.id
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
        updateMenuText(item.displayText)
        if pasteAfter {
          if !Clipboard.shared.paste() {
            AppState.shared.appDelegate?.showTransientStatus("需要辅助功能权限才能自动粘贴")
          }
        }
      case .failure(let error):
        logger.warning("Failed to prepare clipboard payload for item \(itemID): \(error.localizedDescription)")
        AppState.shared.appDelegate?.showTransientStatus("复制失败")
        return
      }
    }
  }

  private func currentModifierFlags() -> NSEvent.ModifierFlags {
    NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
  }

  @MainActor
  private func checkAccessibilityForPaste() -> Bool {
    if Accessibility.check() {
      return true
    }

    AppState.shared.appDelegate?.showTransientStatus("需要辅助功能权限才能自动粘贴")
    return false
  }

  private func cachedLatestMenuText() -> String {
    menuTextLock.lock()
    let cached = cachedMenuText
    menuTextLock.unlock()

    if let cached {
      return cached
    }

    let latest = ClipboardCoreStore.shared.latestUnpinnedDisplayText() ?? ""
    updateMenuText(latest)
    return latest
  }

  private func updateMenuText(_ text: String?) {
    menuTextLock.lock()
    cachedMenuText = text
    menuTextLock.unlock()
  }
}
