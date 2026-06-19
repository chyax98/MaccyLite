import CryptoKit
import Foundation

public struct StoredAsset: Sendable, Equatable {
  public var relativePath: String
  public var hash: String
  public var byteCount: Int

  public init(relativePath: String, hash: String, byteCount: Int) {
    self.relativePath = relativePath
    self.hash = hash
    self.byteCount = byteCount
  }
}

public final class AssetStore: @unchecked Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public func write(_ data: Data, type: String, copiedAt: Date = .now) throws -> StoredAsset {
    let day = Self.dayFormatter.string(from: copiedAt)
    let directory = root.appending(path: day, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let hash = Self.sha256(data)
    let relativePath = "\(day)/\(hash).\(Self.extensionName(for: type))"
    let url = root.appending(path: relativePath)

    if !FileManager.default.fileExists(atPath: url.path) {
      try data.write(to: url, options: .atomic)
    }

    return StoredAsset(relativePath: relativePath, hash: hash, byteCount: data.count)
  }

  public func read(_ relativePath: String) throws -> Data {
    try Data(contentsOf: root.appending(path: relativePath))
  }

  public func readPrefix(_ relativePath: String, byteCount: Int) throws -> Data {
    guard byteCount > 0 else {
      return Data()
    }

    let handle = try FileHandle(forReadingFrom: root.appending(path: relativePath))
    defer {
      try? handle.close()
    }
    return try handle.read(upToCount: byteCount) ?? Data()
  }

  public func exists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: relativePath).path)
  }

  public func remove(_ relativePath: String) throws {
    let url = root.appending(path: relativePath)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  public func allRelativePaths() throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: root.path) else {
      return []
    }

    var paths = Set<String>()
    for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
      let url = root.appending(path: path)
      guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        continue
      }

      paths.insert(path)
    }

    return paths
  }

  public func allRelativePaths(olderThan minimumAge: TimeInterval, now: Date = .now) throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: root.path) else {
      return []
    }

    var paths = Set<String>()
    for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
      let url = root.appending(path: path)
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
      guard values.isRegularFile == true else {
        continue
      }
      guard let modificationDate = values.contentModificationDate else {
        continue
      }
      guard now.timeIntervalSince(modificationDate) >= minimumAge else {
        continue
      }

      paths.insert(path)
    }

    return paths
  }

  public static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter
  }()

  private static func extensionName(for type: String) -> String {
    switch type {
    case ClipboardContentType.plainText:
      return "txt"
    case ClipboardContentType.html:
      return "html"
    case ClipboardContentType.rtf:
      return "rtf"
    case ClipboardContentType.png:
      return "png"
    case ClipboardContentType.tiff:
      return "tiff"
    case ClipboardContentType.jpeg:
      return "jpg"
    case ClipboardContentType.heic:
      return "heic"
    default:
      let sanitized = type
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
      return String(sanitized.prefix(32)).isEmpty ? "bin" : String(sanitized.prefix(32))
    }
  }
}
