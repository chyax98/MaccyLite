import ClipboardCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

guard arguments.count >= 2 else {
  print("""
  Usage:
    clipboard-maintenance health <sqlite-path>
    clipboard-maintenance reindex <sqlite-path>
    clipboard-maintenance search <sqlite-path> <query>
    clipboard-maintenance assets <sqlite-path> <asset-root>
    clipboard-maintenance export <sqlite-path> <asset-root> <export-dir> <yyyy-mm-dd>
    clipboard-maintenance cleanup-assets <sqlite-path> <asset-root> [--apply]
  """)
  exit(2)
}

let command = arguments[0]

switch command {
case "health":
  let database = try openDatabase(arguments[1])
  printHealthReport(try database.healthReport())
case "reindex":
  let database = try openDatabase(arguments[1])
  try database.rebuildSearchIndexes()
  printHealthReport(try database.healthReport())
case "search":
  guard arguments.count >= 3 else {
    print("Usage: clipboard-maintenance search <sqlite-path> <query>")
    exit(2)
  }

  let database = try openDatabase(arguments[1])
  let results = try database.search(arguments[2], limit: 20)
  print("results=\(results.count)")
  for item in results {
    print("\(item.id)\t\(item.primaryType)\t\(item.displayText.prefix(120))")
  }
case "export":
  guard arguments.count >= 5 else {
    print("Usage: clipboard-maintenance export <sqlite-path> <asset-root> <export-dir> <yyyy-mm-dd>")
    exit(2)
  }

  let database = try openDatabase(arguments[1])
  let assetStore = AssetStore(root: URL(fileURLWithPath: arguments[2], isDirectory: true))
  let exportDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
  guard let day = parseDay(arguments[4]) else {
    print("Invalid day: \(arguments[4]). Expected yyyy-mm-dd.")
    exit(2)
  }

  let result = try DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: exportDirectory,
    calendar: Calendar(identifier: .gregorian)
  ).export(day: day)
  print("day=\(formatDay(result.day))")
  print("path=\(result.url.path)")
  print("items=\(result.itemCount)")
case "assets":
  guard arguments.count >= 3 else {
    print("Usage: clipboard-maintenance assets <sqlite-path> <asset-root>")
    exit(2)
  }

  let database = try openDatabase(arguments[1])
  let assetStore = AssetStore(root: URL(fileURLWithPath: arguments[2], isDirectory: true))
  let report = try DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: FileManager.default.temporaryDirectory
  ).assetHealthReport()
  print("healthy=\(report.isHealthy)")
  print("referenced=\(report.referencedCount)")
  print("existing=\(report.existingCount)")
  print("missing=\(report.missing.count)")
  for path in report.missing {
    print("missing\t\(path)")
  }
  print("orphaned=\(report.orphaned.count)")
  for path in report.orphaned {
    print("orphaned\t\(path)")
  }
case "cleanup-assets":
  guard arguments.count >= 3 else {
    print("Usage: clipboard-maintenance cleanup-assets <sqlite-path> <asset-root> [--apply]")
    exit(2)
  }

  let database = try openDatabase(arguments[1])
  let apply = arguments.contains("--apply")
  let assetStore = AssetStore(root: URL(fileURLWithPath: arguments[2], isDirectory: true))
  let exporter = DailyExporter(
    database: database,
    assetStore: assetStore,
    exportDirectory: FileManager.default.temporaryDirectory,
    orphanCleanupMinimumAge: arguments.contains("--unsafe-now") ? 0 : 300
  )
  let paths = apply
    ? try exporter.removeOrphanAssets()
    : try exporter.orphanAssetPaths()
  print(apply ? "removed=\(paths.count)" : "would_remove=\(paths.count)")
  for path in paths {
    print(path)
  }
default:
  print("Unknown command: \(command)")
  exit(2)
}

private func openDatabase(_ path: String) throws -> ClipboardDatabase {
  try ClipboardDatabase(path: URL(fileURLWithPath: path))
}

private func printHealthReport(_ report: ClipboardDatabaseHealthReport) {
  print("healthy=\(report.isHealthy)")
  print("integrity_check=\(report.integrityCheck)")
  print("foreign_key_violations=\(report.foreignKeyViolationCount)")
  print("items=\(report.itemCount)")
  print("contents=\(report.contentCount)")
  print("search_index_rows=\(report.searchIndexCount)")
  print("trigram_index_rows=\(report.trigramIndexCount)")
  print("missing_search_index_rows=\(report.missingSearchIndexCount)")
  print("missing_trigram_index_rows=\(report.missingTrigramIndexCount)")
  print("orphan_search_index_rows=\(report.orphanSearchIndexCount)")
  print("orphan_trigram_index_rows=\(report.orphanTrigramIndexCount)")
}

private func parseDay(_ value: String) -> Date? {
  let parts = value.split(separator: "-").compactMap { Int($0) }
  guard parts.count == 3 else {
    return nil
  }

  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current

  return calendar.date(from: DateComponents(
    calendar: calendar,
    timeZone: calendar.timeZone,
    year: parts[0],
    month: parts[1],
    day: parts[2]
  ))
}

private func formatDay(_ date: Date) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  let components = calendar.dateComponents([.year, .month, .day], from: date)

  return String(
    format: "%04d-%02d-%02d",
    components.year ?? 0,
    components.month ?? 0,
    components.day ?? 0
  )
}
