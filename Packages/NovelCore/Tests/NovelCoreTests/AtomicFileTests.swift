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
}
