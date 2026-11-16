import Foundation
import Testing
@testable import NovelCore

/// 원자적 쓰기. 원고 유실과 바로 이어지는 부분이라 실패 경우까지 확인한다.
struct AtomicFileTests {
  @Test func writesNewFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let file = folder.url.appending(path: "a.md")

    try AtomicFile.write(Data("첫 문장".utf8), to: file)

    #expect(try String(contentsOf: file, encoding: .utf8) == "첫 문장")
  }

  @Test func replacesExistingFileAndLeavesNoTempFiles() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let file = folder.url.appending(path: "a.md")

    try AtomicFile.write(Data("옛 내용".utf8), to: file)
    try AtomicFile.write(Data("새 내용".utf8), to: file)

    #expect(try String(contentsOf: file, encoding: .utf8) == "새 내용")
    #expect(try folder.fileNames(in: folder.url) == ["a.md"])
  }

  @Test func failedWriteKeepsOriginalIntact() throws {
    let folder = try TestFolder()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path(percentEncoded: false))
      folder.remove()
    }
    let file = folder.url.appending(path: "a.md")
    try AtomicFile.write(Data("지켜야 할 원고".utf8), to: file)

    // 폴더를 읽기 전용으로 바꿔 임시 파일을 못 만들게 한다(디스크가 꽉 찬 상황 흉내).
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path(percentEncoded: false))

    #expect(throws: ProjectError.self) {
      try AtomicFile.write(Data("새 내용".utf8), to: file)
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "지켜야 할 원고")
    #expect(try folder.fileNames(in: folder.url) == ["a.md"])
  }

  @Test func writeIntoMissingFolderFailsWithoutCreatingAnything() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let file = folder.url.appending(path: "없는폴더/a.md")

    #expect(throws: ProjectError.self) {
      try AtomicFile.write(Data("x".utf8), to: file)
    }
    #expect(try folder.fileNames(in: folder.url).isEmpty)
  }
  /// 하드 링크를 못 만드는 디스크(exFAT 외장 디스크 등)에서 쓰는 길: 새 이름이면 넣고, 있는 이름이면 덮지 않는다.
  @Test func placeWithoutLinkNeverOverwrites() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let target = folder.url.appending(path: "s.md")
    func temp(_ text: String) throws -> String {
      let url = folder.url.appending(path: ".t-\(UUID().uuidString).tmp")
      try Data(text.utf8).write(to: url)
      return url.path(percentEncoded: false)
    }

    try AtomicFile.placeWithoutLink(temp: try temp("처음"), destination: target.path(percentEncoded: false), url: target)
    #expect(throws: AtomicFile.AlreadyExists.self) {
      try AtomicFile.placeWithoutLink(temp: try temp("나중"), destination: target.path(percentEncoded: false), url: target)
    }

    #expect(try String(contentsOf: target, encoding: .utf8) == "처음")
    #expect(try folder.fileNames(in: folder.url) == ["s.md"], "임시 파일이 남지 않는다")
  }
}

