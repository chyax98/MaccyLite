import AppKit
import ClipboardCore
import ImageIO
import QuickLookThumbnailing

struct TextPreviewPayload: Sendable {
  var text: String
  var isTruncated: Bool

  var characterCount: Int {
    text.count
  }
}

struct FilePreviewPayload: Sendable {
  var text: String
  var image: NSImage?
}

enum HistoryPreviewRenderer {
  static func infoText(for item: ClipboardListItem, characterCount: Int? = nil) -> String {
    var lines = [
      "来源：\(item.sourceApp ?? "未知")",
      "类型：\(readableType(item))",
      "时间：\(item.copiedAt.formatted(date: .numeric, time: .shortened))"
    ]
    if let characterCount {
      lines.insert("字符：\(characterCount)", at: 2)
    }
    return lines.joined(separator: "\n")
  }

  static func readableType(_ item: ClipboardListItem) -> String {
    switch item.primaryType {
    case ClipboardContentType.plainText, ClipboardContentType.legacyPlainText:
      return "文本"
    case ClipboardContentType.fileURL:
      return "文件"
    case ClipboardContentType.html:
      return "HTML"
    case ClipboardContentType.rtf:
      return "富文本"
    default:
      if item.hasImage {
        return "图片"
      }
      return item.primaryType
    }
  }

  static func loadTextPreview(itemID: String, fallback: String) -> TextPreviewPayload {
    guard let item = ClipboardCoreStore.shared.item(id: itemID) else {
      return TextPreviewPayload(text: fallback, isTruncated: false)
    }

    let preferredTypes = [
      ClipboardContentType.plainText,
      ClipboardContentType.legacyPlainText,
      ClipboardContentType.html,
      ClipboardContentType.rtf
    ]

    for type in preferredTypes {
      guard let content = item.contents.first(where: { $0.pasteboardType == type }) else {
        continue
      }

      let shouldReadPrefix = content.byteCount > textPreviewFullReadByteLimit
      guard let data = shouldReadPrefix
        ? ClipboardCoreStore.shared.dataPrefix(for: content, byteCount: textPreviewPrefixByteLimit)
        : ClipboardCoreStore.shared.data(for: content) else {
        continue
      }

      if type == ClipboardContentType.rtf,
         !shouldReadPrefix,
         let attributed = try? NSAttributedString(
          data: data,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
         ) {
        return TextPreviewPayload(text: attributed.string, isTruncated: false)
      }

      if let text = String(data: data, encoding: .utf8) {
        let preview = type == ClipboardContentType.html ? ClipboardTextExtractor.stripHTML(text) : text
        return TextPreviewPayload(text: preview, isTruncated: shouldReadPrefix)
      }
    }

    return TextPreviewPayload(text: fallback, isTruncated: false)
  }

  static func previewText(_ payload: TextPreviewPayload) -> String {
    guard !payload.text.isEmpty else {
      return "没有可预览内容"
    }

    guard payload.isTruncated || payload.text.count > textPreviewCharacterLimit else {
      return payload.text
    }

    return "\(payload.text.shortened(to: textPreviewCharacterLimit))\n\n[内容过长，预览仅显示前 \(textPreviewCharacterLimit) 字；粘贴仍使用完整文本。]"
  }

  static func loadPreviewImage(itemID: String) -> NSImage? {
    guard let item = ClipboardCoreStore.shared.item(id: itemID),
          let content = item.contents.first(where: { imageTypes.contains($0.pasteboardType) }),
          let data = ClipboardCoreStore.shared.data(for: content) else {
      return nil
    }

    return thumbnailImage(from: data, maxPixelSize: 640) ?? NSImage(data: data)
  }

  static func loadFilePreview(itemID: String, scale: CGFloat) async -> FilePreviewPayload {
    guard let item = ClipboardCoreStore.shared.item(id: itemID),
          !item.contents.isEmpty else {
      return FilePreviewPayload(text: "文件", image: nil)
    }

    let urls = item.contents
      .filter { $0.pasteboardType == ClipboardContentType.fileURL }
      .compactMap { content -> URL? in
        guard let data = ClipboardCoreStore.shared.data(for: content),
              let text = String(data: data, encoding: .utf8) else {
          return nil
        }
        return fileURLs(from: text).first
      }

    guard let firstURL = urls.first else {
      return FilePreviewPayload(text: filePreviewText(item.displayText), image: nil)
    }

    let text = filePreviewText(urls: urls)
    if let thumbnail = await quickLookThumbnail(for: firstURL, scale: scale) {
      return FilePreviewPayload(text: text, image: thumbnail)
    }

    let icon = await MainActor.run {
      NSWorkspace.shared.icon(forFile: firstURL.path)
    }
    return FilePreviewPayload(text: text, image: icon)
  }

  static func filePreviewText(_ value: String) -> String {
    let lines = value.split(separator: "\n").map(String.init)
    let paths = lines.map { text -> String in
      guard let url = URL(string: text), url.isFileURL else {
        return text
      }
      return url.path
    }

    return paths.isEmpty ? "文件" : paths.joined(separator: "\n")
  }

  private static func thumbnailImage(from data: Data, maxPixelSize: Int) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: false,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }

    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
  }

  private static func quickLookThumbnail(for url: URL, scale: CGFloat) async -> NSImage? {
    await withCheckedContinuation { continuation in
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: CGSize(width: 256, height: 256),
        scale: scale,
        representationTypes: [.thumbnail, .icon]
      )
      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
        continuation.resume(returning: thumbnail?.nsImage)
      }
    }
  }

  private static func filePreviewText(urls: [URL]) -> String {
    guard !urls.isEmpty else {
      return "文件"
    }

    let paths = urls.map(\.path)
    if paths.count == 1 {
      return paths[0]
    }

    return "\(paths.count) 个文件\n" + paths.prefix(20).joined(separator: "\n")
  }

  private static func fileURLs(from value: String) -> [URL] {
    value
      .split(separator: "\n")
      .compactMap { URL(string: String($0)) }
      .filter(\.isFileURL)
  }

  private static let imageTypes: Set<String> = [
    ClipboardContentType.png,
    ClipboardContentType.tiff,
    ClipboardContentType.jpeg,
    ClipboardContentType.heic
  ]
  private static let textPreviewCharacterLimit = 200_000
  private static let textPreviewFullReadByteLimit = 1_000_000
  private static let textPreviewPrefixByteLimit = 800_000
}
