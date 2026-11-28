// swift-tools-version: 6.4
// NovelCore: data model, file I/O, search, character count, snapshots. Foundation only.
import PackageDescription

let package = Package(
  name: "NovelCore",
  // Including iOS turns any macOS-only API slipping in into an immediate compile error.
  platforms: [.macOS(.v27), .iOS(.v27)],
  products: [
    .library(name: "NovelCore", targets: ["NovelCore"]),
    // Dummy project generator for performance measurement. Not part of the app.
    .executable(name: "make-dummy-novel", targets: ["MakeDummyNovel"]),
  ],
  targets: [
    .target(name: "NovelCore"),
    .executableTarget(name: "MakeDummyNovel", dependencies: ["NovelCore"]),
    .testTarget(name: "NovelCoreTests", dependencies: ["NovelCore"]),
    // Performance measurement. Excluded from normal tests; Scripts/perf.sh runs it in a release build.
    .testTarget(name: "NovelCorePerformanceTests", dependencies: ["NovelCore"]),
  ]
)
