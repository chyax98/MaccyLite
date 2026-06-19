import Foundation

public struct ClipboardContentDraft: Sendable {
  public var pasteboardType: String
  public var byteCount: Int
  public var inlineData: Data?
  public var assetPath: String?
  public var contentHash: String
  public var imageWidth: Int?
  public var imageHeight: Int?

  public init(
    pasteboardType: String,
    byteCount: Int,
    inlineData: Data?,
    assetPath: String?,
    contentHash: String,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil
  ) {
    self.pasteboardType = pasteboardType
    self.byteCount = byteCount
    self.inlineData = inlineData
    self.assetPath = assetPath
    self.contentHash = contentHash
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
  }
}

public struct ClipboardItemDraft: Sendable {
  public var id: String
  public var copiedAt: Date
  public var sourceApp: String?
  public var primaryType: String
  public var displayText: String
  public var searchText: String
  public var contents: [ClipboardContentDraft]

  public init(
    id: String = UUID().uuidString,
    copiedAt: Date = .now,
    sourceApp: String?,
    primaryType: String,
    displayText: String,
    searchText: String,
    contents: [ClipboardContentDraft]
  ) {
    self.id = id
    self.copiedAt = copiedAt
    self.sourceApp = sourceApp
    self.primaryType = primaryType
    self.displayText = displayText
    self.searchText = searchText
    self.contents = contents
  }
}

public struct ClipboardListItem: Sendable, Equatable {
  public var id: String
  public var copiedAt: Date
  public var sourceApp: String?
  public var primaryType: String
  public var displayText: String
  public var isPinned: Bool
  public var copyCount: Int
  public var hasImage: Bool
  public var contentFingerprint: String?

  public init(
    id: String,
    copiedAt: Date,
    sourceApp: String?,
    primaryType: String,
    displayText: String,
    isPinned: Bool,
    copyCount: Int = 1,
    hasImage: Bool = false,
    contentFingerprint: String? = nil
  ) {
    self.id = id
    self.copiedAt = copiedAt
    self.sourceApp = sourceApp
    self.primaryType = primaryType
    self.displayText = displayText
    self.isPinned = isPinned
    self.copyCount = copyCount
    self.hasImage = hasImage
    self.contentFingerprint = contentFingerprint
  }
}

public struct ClipboardStoredContent: Sendable, Equatable {
  public var pasteboardType: String
  public var byteCount: Int
  public var inlineData: Data?
  public var assetPath: String?
  public var contentHash: String
  public var imageWidth: Int?
  public var imageHeight: Int?

  public init(
    pasteboardType: String,
    byteCount: Int,
    inlineData: Data?,
    assetPath: String?,
    contentHash: String,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil
  ) {
    self.pasteboardType = pasteboardType
    self.byteCount = byteCount
    self.inlineData = inlineData
    self.assetPath = assetPath
    self.contentHash = contentHash
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
  }
}

public struct ClipboardStoredItem: Sendable, Equatable {
  public var id: String
  public var copiedAt: Date
  public var sourceApp: String?
  public var primaryType: String
  public var displayText: String
  public var searchText: String
  public var isPinned: Bool
  public var copyCount: Int
  public var contents: [ClipboardStoredContent]

  public init(
    id: String,
    copiedAt: Date,
    sourceApp: String?,
    primaryType: String,
    displayText: String,
    searchText: String,
    isPinned: Bool,
    copyCount: Int,
    contents: [ClipboardStoredContent]
  ) {
    self.id = id
    self.copiedAt = copiedAt
    self.sourceApp = sourceApp
    self.primaryType = primaryType
    self.displayText = displayText
    self.searchText = searchText
    self.isPinned = isPinned
    self.copyCount = copyCount
    self.contents = contents
  }
}
