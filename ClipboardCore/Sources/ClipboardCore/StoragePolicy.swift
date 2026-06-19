import Foundation

public enum ClipboardContentType {
  public static let plainText = "public.utf8-plain-text"
  public static let legacyPlainText = "NSStringPboardType"
  public static let html = "public.html"
  public static let rtf = "public.rtf"
  public static let png = "public.png"
  public static let tiff = "public.tiff"
  public static let jpeg = "public.jpeg"
  public static let heic = "public.heic"
  public static let fileURL = "public.file-url"
}

public struct StoragePolicy: Sendable {
  public var textInlineLimit: Int
  public var richTextInlineLimit: Int
  public var genericInlineLimit: Int
  public var previewLimit: Int
  public var displayCharacterLimit: Int
  public var searchTextLimit: Int
  public var storeImagesAsAssets: Bool

  public init(
    textInlineLimit: Int = 16 * 1024,
    richTextInlineLimit: Int = 32 * 1024,
    genericInlineLimit: Int = 8 * 1024,
    previewLimit: Int = 8 * 1024,
    displayCharacterLimit: Int = 1_000,
    searchTextLimit: Int = 64 * 1024,
    storeImagesAsAssets: Bool = true
  ) {
    self.textInlineLimit = textInlineLimit
    self.richTextInlineLimit = richTextInlineLimit
    self.genericInlineLimit = genericInlineLimit
    self.previewLimit = previewLimit
    self.displayCharacterLimit = displayCharacterLimit
    self.searchTextLimit = searchTextLimit
    self.storeImagesAsAssets = storeImagesAsAssets
  }

  public static let `default` = StoragePolicy()

  public func shouldStoreAsAsset(type: String, byteCount: Int) -> Bool {
    switch normalized(type) {
    case ClipboardContentType.fileURL:
      return false
    case ClipboardContentType.plainText, ClipboardContentType.legacyPlainText:
      return byteCount > textInlineLimit
    case ClipboardContentType.html, ClipboardContentType.rtf:
      return byteCount > richTextInlineLimit
    case ClipboardContentType.png, ClipboardContentType.tiff, ClipboardContentType.jpeg, ClipboardContentType.heic:
      return storeImagesAsAssets
    default:
      return byteCount > genericInlineLimit
    }
  }

  public func inlineData(for data: Data, type: String, storedAsAsset: Bool) -> Data? {
    guard storedAsAsset else {
      return data
    }

    switch normalized(type) {
    case ClipboardContentType.plainText, ClipboardContentType.legacyPlainText:
      return utf8Prefix(data, limit: previewLimit)
    case ClipboardContentType.html, ClipboardContentType.rtf:
      return Data(data.prefix(previewLimit))
    default:
      return nil
    }
  }

  public func displayText(from data: Data, type: String) -> String {
    switch normalized(type) {
    case ClipboardContentType.plainText, ClipboardContentType.legacyPlainText:
      return String(data: Data(data.prefix(previewLimit)), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    case ClipboardContentType.fileURL:
      return String(data: data, encoding: .utf8) ?? "文件"
    case ClipboardContentType.html:
      return "HTML"
    case ClipboardContentType.rtf:
      return "富文本"
    case ClipboardContentType.png, ClipboardContentType.tiff, ClipboardContentType.jpeg, ClipboardContentType.heic:
      return "图片"
    default:
      return normalized(type)
    }
  }

  public func searchableText(from data: Data, type: String) -> String {
    switch normalized(type) {
    case ClipboardContentType.plainText, ClipboardContentType.legacyPlainText:
      return String(data: Data(data.prefix(previewLimit)), encoding: .utf8) ?? ""
    case ClipboardContentType.fileURL:
      return String(data: data, encoding: .utf8) ?? ""
    case ClipboardContentType.html:
      return String(data: Data(data.prefix(previewLimit)), encoding: .utf8) ?? ""
    default:
      return ""
    }
  }

  public func contentDraft(type: String, data: Data, assetStore: AssetStore, copiedAt: Date = .now) throws -> ClipboardContentDraft {
    let storeAsset = shouldStoreAsAsset(type: type, byteCount: data.count)
    let asset = storeAsset ? try assetStore.write(data, type: normalized(type), copiedAt: copiedAt) : nil
    let imageMetadata = imageTypes.contains(normalized(type)) ? ImageMetadataReader.read(from: data) : nil

    return ClipboardContentDraft(
      pasteboardType: normalized(type),
      byteCount: data.count,
      inlineData: inlineData(for: data, type: type, storedAsAsset: asset != nil),
      assetPath: asset?.relativePath,
      contentHash: asset?.hash ?? AssetStore.sha256(data),
      imageWidth: imageMetadata?.width,
      imageHeight: imageMetadata?.height
    )
  }

  private func utf8Prefix(_ data: Data, limit: Int) -> Data {
    guard data.count > limit else {
      return data
    }

    var prefix = data.prefix(limit)
    while String(data: prefix, encoding: .utf8) == nil && !prefix.isEmpty {
      prefix = prefix.dropLast()
    }

    return Data(prefix)
  }

  private func normalized(_ type: String) -> String {
    if type == ClipboardContentType.legacyPlainText {
      return ClipboardContentType.plainText
    }

    return type
  }

  private var imageTypes: Set<String> {
    [
      ClipboardContentType.png,
      ClipboardContentType.tiff,
      ClipboardContentType.jpeg,
      ClipboardContentType.heic
    ]
  }
}
