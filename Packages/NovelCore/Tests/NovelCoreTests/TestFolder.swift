import Foundation

/// Temp folder for tests. Per repo rules, created under the repo's build/ instead of a temp location in the home folder.
struct TestFolder {
  static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // NovelCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // NovelCore
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // Repository root

  let url: URL

  init() throws {
    url = Self.repoRoot.appending(path: "build/tmp/\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }

  /// Includes hidden files.
  func fileNames(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
  }
}
