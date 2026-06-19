import AppKit.NSWorkspace
import ClipboardCore
import Foundation

class HistoryItemDecorator: Identifiable, Hashable {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: AppPreferences.imageMaxHeight) }

  let id = UUID()
  let itemID: String
  var title: String
  private var listItem: ClipboardListItem
  private var fullItem: ClipboardStoredItem?

  var applicationImage: ApplicationImage
  var thumbnailImage: NSImage?
  var previewImage: NSImage?

  var isPinned: Bool {
    listItem.isPinned
  }

  var isUnpinned: Bool {
    !listItem.isPinned
  }

  var hasImage: Bool {
    listItem.hasImage
  }

  var application: String? {
    guard let bundle = listItem.sourceApp,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
      return listItem.sourceApp
    }

    return url.deletingPathExtension().lastPathComponent
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

  private static let imageTypes: Set<NSPasteboard.PasteboardType> = [
    .tiff,
    .png,
    .jpeg,
    .heic
  ]

  init(_ item: ClipboardListItem) {
    self.listItem = item
    self.itemID = item.id
    self.title = item.displayText
    self.applicationImage = ApplicationImageCache.shared.getImage(bundleIdentifier: item.sourceApp)
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
        hasImage: Self.imageContent(in: item) != nil
      )
    )
    self.fullItem = item
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(itemID)
    hasher.combine(title)
  }

  func update(_ item: ClipboardStoredItem) {
    fullItem = item
    listItem = ClipboardListItem(
      id: item.id,
      copiedAt: item.copiedAt,
      sourceApp: item.sourceApp,
      primaryType: item.primaryType,
      displayText: item.displayText,
      isPinned: item.isPinned,
      copyCount: item.copyCount,
      hasImage: Self.imageContent(in: item) != nil
    )
    title = item.displayText
    applicationImage = ApplicationImageCache.shared.getImage(bundleIdentifier: item.sourceApp)
  }

  @MainActor
  func ensureThumbnailImage() {
    guard thumbnailImage == nil, hasImage else {
      return
    }

    let itemID = itemID
    Task {
      let result = await Task.detached(priority: .utility) {
      let storedItem = ClipboardCoreStore.shared.item(id: itemID)
      guard let storedItem,
            let imageData = Self.thumbnailData(for: storedItem),
            let image = NSImage(data: imageData)?.resized(to: Self.thumbnailImageSize) else {
        return nil as (ClipboardStoredItem, NSImage)?
      }

        return (storedItem, image)
      }.value

      guard let result, self.itemID == itemID else {
        return
      }

      update(result.0)
      thumbnailImage = result.1
    }
  }

  @MainActor
  func ensurePreviewImage() {
    Task {
      _ = await asyncGetPreviewImage()
    }
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let previewImage {
      return previewImage
    }

    let itemID = itemID
    let result = await Task.detached(priority: .utility) {
      let storedItem = ClipboardCoreStore.shared.item(id: itemID)
      guard let storedItem,
            let imageData = Self.previewData(for: storedItem),
            let image = NSImage(data: imageData)?.resized(to: Self.previewImageSize) else {
        return nil as (ClipboardStoredItem, NSImage)?
      }

      return (storedItem, image)
    }.value

    guard let result else {
      return nil
    }

    update(result.0)
    previewImage = result.1
    thumbnailImage = thumbnailImage ?? result.1.resized(to: Self.thumbnailImageSize)
    return result.1
  }

  @MainActor
  func cleanupImages() {
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
  }

  @MainActor
  func sizeImages() {
    thumbnailImage = thumbnailImage?.resized(to: Self.thumbnailImageSize)
    previewImage = previewImage?.resized(to: Self.previewImageSize)
  }

  @MainActor
  func togglePin() {
    listItem.isPinned.toggle()
    let isPinned = listItem.isPinned
    if var fullItem {
      fullItem.isPinned = isPinned
      self.fullItem = fullItem
    }
    let itemID = itemID
    Task.detached(priority: .utility) {
      ClipboardCoreStore.shared.setPinned(isPinned, itemID: itemID)
    }
  }

  private static func thumbnailData(for item: ClipboardStoredItem) -> Data? {
    guard let content = imageContent(in: item) else {
      return nil
    }

    if let thumbnailPath = content.thumbnailPath,
       let data = ClipboardCoreStore.shared.data(assetPath: thumbnailPath) {
      return data
    }

    return nil
  }

  private static func previewData(for item: ClipboardStoredItem) -> Data? {
    guard let content = imageContent(in: item) else {
      return nil
    }

    if let thumbnailPath = content.thumbnailPath,
       let data = ClipboardCoreStore.shared.data(assetPath: thumbnailPath) {
      return data
    }

    return nil
  }

  private static func imageContent(in item: ClipboardStoredItem) -> ClipboardStoredContent? {
    item.contents.first { content in
      Self.imageTypes.contains(NSPasteboard.PasteboardType(content.pasteboardType))
    }
  }
}
