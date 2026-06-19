import ClipboardCore
import Foundation

class HistoryItemDecorator: Identifiable, Hashable {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  let id = UUID()
  let itemID: String
  var title: String
  private var listItem: ClipboardListItem

  var isPinned: Bool {
    listItem.isPinned
  }

  var isUnpinned: Bool {
    !listItem.isPinned
  }

  var text: String {
    listItem.displayText.shortened(to: 10_000)
  }

  var copiedAt: Date {
    listItem.copiedAt
  }

  var copyCount: Int {
    listItem.copyCount
  }

  init(_ item: ClipboardListItem) {
    self.listItem = item
    self.itemID = item.id
    self.title = item.displayText
  }

  convenience init(_ item: ClipboardStoredItem) {
    self.init(
      ClipboardListItem(
        id: item.id,
        copiedAt: item.copiedAt,
        sourceApp: item.sourceApp,
        primaryType: item.primaryType,
        displayText: item.displayText,
        isPinned: item.isPinned,
        copyCount: item.copyCount,
        hasImage: item.contents.contains { $0.imageWidth != nil || $0.imageHeight != nil }
      )
    )
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(itemID)
    hasher.combine(title)
  }

  @MainActor
  func togglePin() {
    listItem.isPinned.toggle()
    let isPinned = listItem.isPinned
    let itemID = itemID
    Task.detached(priority: .utility) {
      ClipboardCoreStore.shared.setPinned(isPinned, itemID: itemID)
    }
  }
}
