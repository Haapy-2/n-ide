import Foundation

/// 테스트용 임시 폴더. 저장소 규칙대로 홈 폴더 임시 위치가 아니라 저장소의 build/ 아래에 만든다.
struct TestFolder {
  static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // NovelCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // NovelCore
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // 저장소 루트

  let url: URL

  init() throws {
    url = Self.repoRoot.appending(path: "build/tmp/\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }

  /// 폴더 안 파일 이름 목록 (숨김 파일 포함).
  func fileNames(in folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
  }
}
