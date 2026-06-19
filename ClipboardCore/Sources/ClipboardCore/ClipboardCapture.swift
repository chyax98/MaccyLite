import Foundation

public struct ClipboardRawContent: Sendable, Equatable {
  public var pasteboardType: String
  public var data: Data

  public init(pasteboardType: String, data: Data) {
    self.pasteboardType = pasteboardType
    self.data = data
  }
}

public struct ClipboardCapture: Sendable {
  public var policy: StoragePolicy
  public var assetStore: AssetStore

  public init(policy: StoragePolicy = .default, assetStore: AssetStore) {
    self.policy = policy
    self.assetStore = assetStore
  }

  public func makeItem(
    contents rawContents: [ClipboardRawContent],
    sourceApp: String?,
    copiedAt: Date = .now
  ) throws -> ClipboardItemDraft? {
    let normalized = normalize(rawContents)
    guard !normalized.isEmpty else {
      return nil
    }

    let ordered = normalized.sorted { lhs, rhs in
      priority(lhs.pasteboardType) < priority(rhs.pasteboardType)
    }

    let drafts = try ordered.map { raw in
      try policy.contentDraft(
        type: raw.pasteboardType,
        data: raw.data,
        assetStore: assetStore,
        copiedAt: copiedAt
      )
    }

    let primary = ordered[0]
    let displayText = displayText(for: ordered)
    let searchText = searchText(for: ordered)

    return ClipboardItemDraft(
      copiedAt: copiedAt,
      sourceApp: sourceApp,
      primaryType: primary.pasteboardType,
      displayText: displayText,
      searchText: searchText,
      contents: drafts
    )
  }

  private func normalize(_ contents: [ClipboardRawContent]) -> [ClipboardRawContent] {
    var seen = Set<NormalizedContentKey>()
    var normalized: [ClipboardRawContent] = []

    for content in contents {
      let type = normalizeType(content.pasteboardType)
      let keyData: Data? = type == ClipboardContentType.fileURL ? content.data : nil
      let key = NormalizedContentKey(
        type: type,
        data: keyData
      )
      guard !content.data.isEmpty, !seen.contains(key) else {
        continue
      }

      seen.insert(key)
      normalized.append(ClipboardRawContent(pasteboardType: type, data: content.data))
    }

    return normalized
  }

  private func displayText(for contents: [ClipboardRawContent]) -> String {
    for type in displayPriorityTypes {
      guard let content = contents.first(where: { $0.pasteboardType == type }) else {
        continue
      }

      let text = extractedText(from: content.data, type: content.pasteboardType)
      if !text.isEmpty {
        return String(text.prefix(policy.displayCharacterLimit))
      }
    }

    return policy.displayText(from: contents[0].data, type: contents[0].pasteboardType)
  }

  private func searchText(for contents: [ClipboardRawContent]) -> String {
    let hasPlainText = contents.contains { $0.pasteboardType == ClipboardContentType.plainText }
    return contents
      .filter { content in
        guard hasPlainText else { return true }
        return content.pasteboardType != ClipboardContentType.html &&
          content.pasteboardType != ClipboardContentType.rtf
      }
      .map { extractedText(from: $0.data, type: $0.pasteboardType) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  private func extractedText(from data: Data, type: String) -> String {
    switch type {
    case ClipboardContentType.plainText:
      return utf8PrefixString(data, limit: policy.searchTextLimit)
    case ClipboardContentType.fileURL:
      return String(data: data, encoding: .utf8) ?? ""
    case ClipboardContentType.html:
      let html = utf8PrefixString(data, limit: min(policy.searchTextLimit, policy.richTextSearchTextLimit))
      return stripHTML(html)
    case ClipboardContentType.rtf:
      return ""
    default:
      return ""
    }
  }

  private func stripHTML(_ html: String) -> String {
    var text = ""
    text.reserveCapacity(min(html.count, policy.richTextSearchTextLimit))
    var isInsideTag = false
    var previousWasWhitespace = false
    var index = html.startIndex

    while index < html.endIndex {
      let character = html[index]

      if character == "<" {
        isInsideTag = true
        appendSpace(to: &text, previousWasWhitespace: &previousWasWhitespace)
      } else if character == ">" {
        isInsideTag = false
      } else if !isInsideTag {
        if character.isWhitespace {
          appendSpace(to: &text, previousWasWhitespace: &previousWasWhitespace)
        } else {
          text.append(character)
          previousWasWhitespace = false
        }
      }

      index = html.index(after: index)
    }

    return text
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func appendSpace(to text: inout String, previousWasWhitespace: inout Bool) {
    guard !previousWasWhitespace, !text.isEmpty else {
      return
    }

    text.append(" ")
    previousWasWhitespace = true
  }

  private func utf8PrefixString(_ data: Data, limit: Int) -> String {
    guard data.count > limit else {
      return String(data: data, encoding: .utf8) ?? ""
    }

    var prefix = data.prefix(limit)
    while String(data: prefix, encoding: .utf8) == nil && !prefix.isEmpty {
      prefix = prefix.dropLast()
    }

    return String(data: prefix, encoding: .utf8) ?? ""
  }

  private func priority(_ type: String) -> Int {
    switch type {
    case ClipboardContentType.plainText:
      return 0
    case ClipboardContentType.fileURL:
      return 1
    case ClipboardContentType.html:
      return 2
    case ClipboardContentType.rtf:
      return 3
    case ClipboardContentType.png, ClipboardContentType.tiff, ClipboardContentType.jpeg, ClipboardContentType.heic:
      return 4
    default:
      return 10
    }
  }

  private func normalizeType(_ type: String) -> String {
    if type == ClipboardContentType.legacyPlainText {
      return ClipboardContentType.plainText
    }

    return type
  }

  private let displayPriorityTypes = [
    ClipboardContentType.plainText,
    ClipboardContentType.fileURL,
    ClipboardContentType.html,
    ClipboardContentType.rtf,
    ClipboardContentType.png,
    ClipboardContentType.tiff,
    ClipboardContentType.jpeg,
    ClipboardContentType.heic
  ]
}

private struct NormalizedContentKey: Hashable {
  var type: String
  var data: Data?
}
