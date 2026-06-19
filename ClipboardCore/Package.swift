// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ClipboardCore",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
    .executable(name: "clipboard-benchmark", targets: ["ClipboardBenchmark"]),
    .executable(name: "clipboard-maintenance", targets: ["ClipboardMaintenance"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.5.0")
  ],
  targets: [
    .target(
      name: "ClipboardCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
      ]
    ),
    .testTarget(
      name: "ClipboardCoreTests",
      dependencies: ["ClipboardCore"]
    ),
    .executableTarget(
      name: "ClipboardBenchmark",
      dependencies: ["ClipboardCore"]
    ),
    .executableTarget(
      name: "ClipboardMaintenance",
      dependencies: ["ClipboardCore"]
    )
  ]
)
