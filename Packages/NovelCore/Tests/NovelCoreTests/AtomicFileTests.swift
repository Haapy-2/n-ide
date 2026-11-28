import Foundation
import Testing
@testable import NovelCore

/// Atomic writes. Directly tied to manuscript loss, so failure cases are checked too.
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

    // Make the folder read-only so the temp file can't be created (simulating a full disk).
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
  /// Path used on disks that can't make hard links (exFAT external disks etc.): insert if the name is new, never overwrite an existing name.
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


/// Classify save failure causes so the app picks fitting guidance.
struct WriteProblemTests {
  @Test func readOnlyFolderIsNoPermission() throws {
    let folder = try TestFolder()
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path(percentEncoded: false))
      folder.remove()
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path(percentEncoded: false))

    #expect(problem { try AtomicFile.write(Data("x".utf8), to: folder.url.appending(path: "a.md")) } == .noPermission)
  }

  @Test func lockedFileIsLocked() throws {
    let folder = try TestFolder()
    let file = folder.url.appending(path: "a.md")
    defer {
      try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path(percentEncoded: false))
      folder.remove()
    }
    try AtomicFile.write(Data("원래".utf8), to: file)
    try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path(percentEncoded: false))

    #expect(problem { try AtomicFile.write(Data("새 글".utf8), to: file) } == .locked)
    #expect(try String(contentsOf: file, encoding: .utf8) == "원래")
  }

  @Test func missingFolderIsMissingFolder() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    #expect(problem { try AtomicFile.write(Data("x".utf8), to: folder.url.appending(path: "없는 폴더/a.md")) } == .missingFolder)
  }

  @Test func errnoAndCocoaCodesMap() {
    #expect(WriteProblem(errno: ENOSPC) == .diskFull)
    #expect(WriteProblem(errno: EDQUOT) == .diskFull)
    #expect(WriteProblem(errno: EROFS) == .readOnlyVolume)
    #expect(WriteProblem(errno: EIO) == .other)
    #expect(WriteProblem(error: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)) == .diskFull)
    let wrapped = NSError(
      domain: NSCocoaErrorDomain, code: 512,
      userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
    #expect(WriteProblem(error: wrapped) == .noPermission)
  }

  private func problem(_ work: () throws -> Void) -> WriteProblem? {
    do {
      try work()
      return nil
    } catch ProjectError.writeFailed(_, _, let problem) {
      return problem
    } catch {
      return nil
    }
  }
}
