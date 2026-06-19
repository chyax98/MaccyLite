import Foundation

public struct ClipboardPasteboardPayload: Sendable, Equatable {
  public var pasteboardType: String
  public var data: Data

  public init(pasteboardType: String, data: Data) {
    self.pasteboardType = pasteboardType
    self.data = data
  }
}

public enum ClipboardPasteboardPayloadError: Error, Sendable, Equatable {
  case missingAsset(String)
}

public struct ClipboardPasteboardPayloadResolver: Sendable {
  private let stringType: String
  private let fileURLType: String
  private let readAsset: @Sendable (String) throws -> Data

  public init(
    stringType: String = ClipboardContentType.plainText,
    fileURLType: String = ClipboardContentType.fileURL,
    readAsset: @escaping @Sendable (String) throws -> Data
  ) {
    self.stringType = stringType
    self.fileURLType = fileURLType
    self.readAsset = readAsset
  }

  public func payloads(
    for item: ClipboardStoredItem,
    removeFormatting: Bool = false
  ) throws -> [ClipboardPasteboardPayload] {
    let contents = filteredContents(item.contents, removeFormatting: removeFormatting)

    return try contents.map { content in
      ClipboardPasteboardPayload(
        pasteboardType: content.pasteboardType,
        data: try data(for: content)
      )
    }
  }

  private func filteredContents(
    _ contents: [ClipboardStoredContent],
    removeFormatting: Bool
  ) -> [ClipboardStoredContent] {
    guard removeFormatting else {
      return contents
    }

    let stringContents = contents.filter { $0.pasteboardType == stringType }
    guard !stringContents.isEmpty else {
      return contents
    }

    let fileURLContents = contents.filter { $0.pasteboardType == fileURLType }
    return stringContents + fileURLContents
  }

  private func data(for content: ClipboardStoredContent) throws -> Data {
    if let assetPath = content.assetPath {
      return try readAsset(assetPath)
    }

    guard let inlineData = content.inlineData else {
      throw ClipboardPasteboardPayloadError.missingAsset(content.pasteboardType)
    }

    return inlineData
  }
}
