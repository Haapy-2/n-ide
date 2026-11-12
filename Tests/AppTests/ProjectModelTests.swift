import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

/// 회차 관리: 추가, 이름 변경, 순서 변경, 휴지통으로 보내기. 바뀐 목록이 project.json에 저장되는지까지 본다.
@MainActor
final class ProjectModelTests: XCTestCase {
  private var folder: URL!
  private var trash: URL!
  private var store: ProjectStore!

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    trash = folder.appending(path: "휴지통")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  /// 진짜 휴지통 대신 테스트 폴더 안 "휴지통"으로 옮기는 모델.
  private func makeModel(trashFails: Bool = false) throws -> ProjectModel {
    let trash = trash!
    return ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      autosaveDelay: .milliseconds(20),
      moveToTrash: { url in
        if trashFails { throw CocoaError(.fileWriteNoPermission) }
        let destination = trash.appending(path: url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
      })
  }

  func testAddEpisodeCreatesEmptyFileAndSavesList() async throws {
    let model = try makeModel()

    let first = try await model.addEpisode()
    let second = try await model.addEpisode()
    let middle = try await model.addEpisode(after: first)

    XCTAssertEqual(model.episodes.map(\.id), [first, middle, second])
    XCTAssertEqual(try store.readEpisode(middle), "")
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [first, middle, second])
    XCTAssertEqual(model.episodes[0].goal, 5_000)
  }

  func testRenameTrimsAndSaves() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()

    await model.rename(id, to: "  첫 만남 \n")

    XCTAssertEqual(model.episode(id)?.title, "첫 만남")
    XCTAssertEqual(try store.loadProject().episodes.first?.title, "첫 만남")
  }

  func testMoveChangesOrderButNotFileNames() async throws {
    let model = try makeModel()
    let a = try await model.addEpisode()
    let b = try await model.addEpisode()
    let c = try await model.addEpisode()

    await model.moveEpisodes(fromOffsets: IndexSet(integer: 2), toOffset: 0)

    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [c, a, b])
    let files = try FileManager.default.contentsOfDirectory(atPath: store.layout.episodesFolder.path(percentEncoded: false))
    XCTAssertEqual(Set(files), Set([a, b, c].map { "\($0.rawValue).md" }))
  }

  func testTrashMovesFileAndRemovesFromList() async throws {
    let model = try makeModel()
    let keep = try await model.addEpisode()
    let gone = try await model.addEpisode()
    try store.writeEpisode("지울 회차 본문", id: gone)

    try await model.trashEpisode(gone)

    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [keep])
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.layout.episodeFile(gone).path(percentEncoded: false)))
    let trashed = trash.appending(path: "\(gone.rawValue).md")
    XCTAssertEqual(try String(contentsOf: trashed, encoding: .utf8), "지울 회차 본문", "휴지통에서 되살릴 수 있어야 한다")
  }

  /// 휴지통으로 못 옮기면 지우기를 멈춘다. 파일도 목록도 그대로이고, 영구 삭제로 대신하지 않는다.
  func testTrashFailureChangesNothing() async throws {
    let model = try makeModel(trashFails: true)
    let id = try await model.addEpisode()
    try store.writeEpisode("지키는 본문", id: id)

    do {
      try await model.trashEpisode(id)
      XCTFail("오류가 나야 한다")
    } catch {}

    XCTAssertEqual(model.episodes.map(\.id), [id])
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [id])
    XCTAssertEqual(try store.readEpisode(id), "지키는 본문")
  }

  /// 편집 중이던 회차를 지우면, 지우기 전에 마지막 내용을 저장해 휴지통에 넣고, 지운 뒤에 파일이 되살아나지 않는다.
  func testTrashingEditedEpisodeSavesFirstAndDoesNotResurrect() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "고치던 중")
    model.autosaver.attach(textView)
    model.autosaver.begin(episode: id)
    textView.insertText(" 마지막 문장", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
    model.autosaver.textDidChange()

    try await model.trashEpisode(id)
    try await Task.sleep(for: .milliseconds(100))  // 자동 저장 지연(20ms)이 지나도록

    let trashed = trash.appending(path: "\(id.rawValue).md")
    XCTAssertEqual(try String(contentsOf: trashed, encoding: .utf8), "고치던 중 마지막 문장")
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.layout.episodeFile(id).path(percentEncoded: false)))
    XCTAssertFalse(model.autosaver.hasUnsavedChanges)
  }

  /// 드래그로 바꾼 순서를 ⌘Z로 직전 순서로 되돌리고, ⇧⌘Z로 다시 바꾼다. 저장된 목록도 따라간다.
  func testUndoAndRedoReorder() async throws {
    let model = try makeModel()
    let a = try await model.addEpisode()
    let b = try await model.addEpisode()
    let c = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false

    undo.beginUndoGrouping()
    await model.moveEpisodes(fromOffsets: IndexSet(integer: 2), toOffset: 0, undoManager: undo)
    undo.endUndoGrouping()
    XCTAssertEqual(model.episodes.map(\.id), [c, a, b])
    XCTAssertEqual(undo.undoActionName, "순서 변경")

    undo.undo()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(model.episodes.map(\.id), [a, b, c])
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [a, b, c])

    undo.redo()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(model.episodes.map(\.id), [c, a, b])
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [c, a, b])
  }

  func testUndoRename() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false

    undo.beginUndoGrouping()
    await model.rename(id, to: "새 제목", undoManager: undo)
    undo.endUndoGrouping()
    undo.undo()
    try await Task.sleep(for: .milliseconds(100))

    XCTAssertEqual(model.episode(id)?.title, "")
    XCTAssertEqual(try store.loadProject().episodes.first?.title, "")
  }

  private func grouped(_ undo: UndoManager, _ work: () async throws -> Void) async rethrows {
    undo.beginUndoGrouping()
    try await work()
    undo.endUndoGrouping()
  }

  /// 실수로 만든 새 회차를 ⌘Z로 없애고(휴지통), ⇧⌘Z로 다시 꺼낸다.
  func testUndoAddEpisode() async throws {
    let model = try makeModel()
    let first = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false
    var added: EpisodeID!
    try await grouped(undo) { added = try await model.addEpisode(after: first, undoManager: undo) }
    XCTAssertEqual(undo.undoActionName, "새 회차")

    undo.undo()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(model.episodes.map(\.id), [first])
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [first])
    XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "\(added.rawValue).md").path(percentEncoded: false)))

    undo.redo()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(model.episodes.map(\.id), [first, added])
    XCTAssertEqual(try store.readEpisode(added), "")
  }

  /// 휴지통으로 보낸 회차를 ⌘Z로 꺼내 원래 자리와 본문 그대로 되돌리고, ⇧⌘Z로 다시 휴지통에 보낸다.
  func testUndoTrashRestoresFileAndPosition() async throws {
    let model = try makeModel()
    let a = try await model.addEpisode()
    let b = try await model.addEpisode()
    let c = try await model.addEpisode()
    try store.writeEpisode("되살릴 본문", id: b)
    let undo = UndoManager()
    undo.groupsByEvent = false

    try await grouped(undo) { try await model.trashEpisode(b, undoManager: undo) }
    XCTAssertEqual(model.episodes.map(\.id), [a, c])

    undo.undo()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(model.episodes.map(\.id), [a, b, c])
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), [a, b, c])
    XCTAssertEqual(try store.readEpisode(b), "되살릴 본문")

    undo.redo()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(model.episodes.map(\.id), [a, c])
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.layout.episodeFile(b).path(percentEncoded: false)))
  }

  /// "새 회차에도 쓰기": 작품 기본 목표가 project.json에 저장되고 그 뒤 만드는 회차가 그 목표로 시작한다.
  /// 회차 목표와 함께 바꾸면 ⌘Z 한 번에 둘 다 되돌아간다.
  func testDefaultEpisodeGoalAppliesToNewEpisodesAndUndoesWithGoal() async throws {
    let model = try makeModel()
    let first = try await model.addEpisode()
    let undo = UndoManager()
    undo.groupsByEvent = false

    try await grouped(undo) {
      model.setDefaultEpisodeGoal(3_000, undoManager: undo)
      await model.setGoal(first, to: 3_000, undoManager: undo)
    }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(try store.loadProject().settings.defaultEpisodeGoal, 3_000)

    undo.undo()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(model.project.settings.defaultEpisodeGoal, 5_000)
    XCTAssertEqual(model.episode(first)?.goal, 5_000)
    XCTAssertEqual(try store.loadProject().settings.defaultEpisodeGoal, 5_000)

    undo.redo()
    try await Task.sleep(for: .milliseconds(100))
    let second = try await model.addEpisode()
    XCTAssertEqual(model.episode(first)?.goal, 3_000)
    XCTAssertEqual(model.episode(second)?.goal, 3_000)
  }

  func testDefaultEpisodeGoalIgnoresZero() async throws {
    let model = try makeModel()
    await model.setDefaultEpisodeGoal(0).value
    XCTAssertEqual(model.project.settings.defaultEpisodeGoal, 5_000)
  }
}
