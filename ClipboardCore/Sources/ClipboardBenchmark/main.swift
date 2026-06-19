import ClipboardCore
import Foundation

private let arguments = CommandLine.arguments.dropFirst()
private let options = BenchmarkOptions(arguments: Array(arguments))
private let mode = options.mode
private let itemCount = options.itemCount ?? (mode == "mixed" ? 10_000 : 100_000)
private let root = FileManager.default.temporaryDirectory
  .appending(path: "ClipboardCoreBenchmark-\(UUID().uuidString)", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

private let assetStore = AssetStore(root: root.appending(path: "Assets"))
private let database = try ClipboardDatabase(path: root.appending(path: "Clipboard.sqlite"))
private let capture = ClipboardCapture(assetStore: assetStore)
private let startedAt = ContinuousClock.now

switch mode {
case "mixed":
  try insertMixedItems(count: itemCount, database: database, capture: capture)
default:
  try insertTextItems(count: itemCount, database: database)
}

private let insertedAt = ContinuousClock.now

var latestSamples: [Double] = []
var cjkSearchSamples: [Double] = []
var tokenSearchSamples: [Double] = []
var pendingThumbnailSamples: [Double] = []
var pendingThumbnails = 0

for _ in 0..<options.runs {
  latestSamples.append(try measure {
    _ = try database.latest(limit: 50)
  })

  cjkSearchSamples.append(try measure {
    _ = try database.search("数据库", limit: 50)
  })

  tokenSearchSamples.append(try measure {
    _ = try database.search("example", limit: 50)
  })

  pendingThumbnailSamples.append(try measure {
    pendingThumbnails = try database.pendingThumbnailJobs(limit: itemCount).count
  })
}

private let assetBytes = byteCount(at: assetStore.root)

print("mode=\(mode)")
print("items=\(itemCount)")
print("runs=\(options.runs)")
print("insert_ms=\(startedAt.duration(to: insertedAt).milliseconds)")
printStats("latest", latestSamples)
printStats("cjk_search", cjkSearchSamples)
printStats("token_search", tokenSearchSamples)
print("pending_thumbnail_jobs=\(pendingThumbnails)")
printStats("pending_thumbnail_jobs", pendingThumbnailSamples)
print("asset_bytes=\(assetBytes)")

private struct BenchmarkOptions {
  let itemCount: Int?
  let mode: String
  let runs: Int

  init(arguments: [String]) {
    var positional: [String] = []
    var parsedRuns = 20
    var index = 0

    while index < arguments.count {
      switch arguments[index] {
      case "--runs":
        if arguments.indices.contains(index + 1), let value = Int(arguments[index + 1]) {
          parsedRuns = value
          index += 2
        } else {
          index += 1
        }
      default:
        positional.append(arguments[index])
        index += 1
      }
    }

    itemCount = positional.first.flatMap(Int.init)
    mode = positional.dropFirst().first ?? "text"
    runs = max(1, parsedRuns)
  }
}

private func measure(_ operation: () throws -> Void) rethrows -> Double {
  let start = ContinuousClock.now
  try operation()
  return start.duration(to: ContinuousClock.now).milliseconds
}

private func printStats(_ name: String, _ samples: [Double]) {
  let stats = BenchmarkStats(samples: samples)
  print("\(name)_ms=\(stats.p50)")
  print("\(name)_min_ms=\(stats.min)")
  print("\(name)_p50_ms=\(stats.p50)")
  print("\(name)_p95_ms=\(stats.p95)")
  print("\(name)_max_ms=\(stats.max)")
}

private struct BenchmarkStats {
  let min: Double
  let p50: Double
  let p95: Double
  let max: Double

  init(samples: [Double]) {
    let sorted = samples.sorted()
    min = sorted.first ?? 0
    p50 = Self.percentile(0.50, sorted: sorted)
    p95 = Self.percentile(0.95, sorted: sorted)
    max = sorted.last ?? 0
  }

  private static func percentile(_ percentile: Double, sorted: [Double]) -> Double {
    guard !sorted.isEmpty else { return 0 }
    guard sorted.count > 1 else { return sorted[0] }

    let position = percentile * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))

    if lower == upper {
      return sorted[lower]
    }

    let weight = position - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
  }
}

private func insertTextItems(count: Int, database: ClipboardDatabase) throws {
  for index in 0..<count {
    let text = "第\(index)条 剪贴板 数据库 URL https://example.com/item/\(index)"
    let data = Data(text.utf8)
    try database.insert(ClipboardItemDraft(
      copiedAt: Date(timeIntervalSince1970: TimeInterval(index)),
      sourceApp: "benchmark",
      primaryType: ClipboardContentType.plainText,
      displayText: text,
      searchText: text,
      contents: [
        ClipboardContentDraft(
          pasteboardType: ClipboardContentType.plainText,
          byteCount: data.count,
          inlineData: data,
          assetPath: nil,
          contentHash: AssetStore.sha256(data)
        )
      ]
    ))
  }
}

private func insertMixedItems(count: Int, database: ClipboardDatabase, capture: ClipboardCapture) throws {
  for index in 0..<count {
    let copiedAt = Date(timeIntervalSince1970: TimeInterval(index))
    let rawContents: [ClipboardRawContent]

    switch index % 6 {
    case 0:
      rawContents = [
        ClipboardRawContent(
          pasteboardType: ClipboardContentType.plainText,
          data: Data("第\(index)条 短文本 数据库 example token-\(index)".utf8)
        )
      ]
    case 1:
      rawContents = [
        ClipboardRawContent(
          pasteboardType: ClipboardContentType.plainText,
          data: Data(longText(index: index).utf8)
        )
      ]
    case 2:
      rawContents = [
        ClipboardRawContent(
          pasteboardType: ClipboardContentType.html,
          data: Data("<article><h1>数据库 \(index)</h1><a href=\"https://example.com/html/\(index)\">example</a><p>HTML 内容</p></article>".utf8)
        )
      ]
    case 3:
      rawContents = [
        ClipboardRawContent(
          pasteboardType: ClipboardContentType.rtf,
          data: Data("{\\rtf1\\ansi benchmark \(index)}".utf8)
        )
      ]
    case 4:
      rawContents = [
        ClipboardRawContent(
          pasteboardType: ClipboardContentType.fileURL,
          data: Data("file:///Users/xd/Desktop/example-\(index).txt".utf8)
        )
      ]
    default:
      rawContents = [
        ClipboardRawContent(
          pasteboardType: ClipboardContentType.png,
          data: onePixelPNG()
        )
      ]
    }

    if let item = try capture.makeItem(contents: rawContents, sourceApp: "benchmark.mixed", copiedAt: copiedAt) {
      try database.insert(item)
    }
  }
}

private func longText(index: Int) -> String {
  let chunk = "第\(index)条 长文本 数据库 example https://example.com/long/\(index)\n"
  return String(repeating: chunk, count: 1_000)
}

private func onePixelPNG() -> Data {
  Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
}

private func byteCount(at url: URL) -> Int64 {
  guard let enumerator = FileManager.default.enumerator(
    at: url,
    includingPropertiesForKeys: [.fileSizeKey],
    options: [.skipsHiddenFiles]
  ) else {
    return 0
  }

  return enumerator.compactMap { entry -> Int64? in
    guard let url = entry as? URL,
          let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else {
      return nil
    }
    return Int64(values.fileSize ?? 0)
  }.reduce(0, +)
}

private extension Duration {
  var milliseconds: Double {
    Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
