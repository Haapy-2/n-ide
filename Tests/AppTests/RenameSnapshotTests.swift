import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

/// Every rename leaves a per-episode `rename` snapshot (body at that time, old title, memo).
@MainActor
final class RenameSnapshotTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeModel(titles: [String]) async throws -> (ProjectModel, [EpisodeID]) {
    let model = ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      autosaveDelay: .milliseconds(20))
    var ids: [EpisodeID] = []
    for (index, title) in titles.enumerated() {
      let id = try await model.addEpisode()
      try store.writeEpisode("본문 \(index)", id: id)
      await model.renameEpisodes([id: title], reason: .single)
      ids.append(id)
    }
    // Rename snapshots created during setup are deleted (the test looks only at later ones).
    for id in ids { try? FileManager.default.removeItem(at: store.layout.snapshotFolder(id)) }
    return (model, ids)
  }

  private func renames(_ id: EpisodeID) throws -> [(body: String, title: String?, memo: String?)] {
    try store.snapshots(of: id).filter { $0.kind == .rename }.map {
      (try store.readSnapshot($0), store.readTitle($0), store.readMemo($0))
    }
  }

  func testBatchRenameSnapshotsOnlyChangedEpisodes() async throws {
    let (model, ids) = try await makeModel(titles: ["가", "나", "다"])

    let outcome = await model.renameEpisodes([ids[0]: "프롤로그 1", ids[1]: " 나 ", ids[2]: ""], reason: .batch)

    XCTAssertEqual(outcome, .init(renamed: 2, unsnapshotted: 0))
    XCTAssertEqual(model.episodes.map(\.title), ["프롤로그 1", "나", ""])
    XCTAssertEqual(try store.loadProject().episodes.map(\.title), ["프롤로그 1", "나", ""])
    let first = try renames(ids[0])
    XCTAssertEqual(first.map(\.body), ["본문 0"])
    XCTAssertEqual(first.map(\.title), ["가"])
    XCTAssertEqual(first.map(\.memo), ["'가' → '프롤로그 1' · 2개 회차 함께"])
    XCTAssertTrue(try renames(ids[1]).isEmpty, "공백만 다른 이름은 바뀌지 않아 스냅샷도 없다")
    XCTAssertEqual(try renames(ids[2]).map(\.memo), ["'다' → (제목 없음) · 2개 회차 함께"])
  }

  /// The sheet's rule applies in current list order (numbers follow list order regardless of selection order).
  func testRuleAppliesInListOrder() async throws {
    let (model, ids) = try await makeModel(titles: ["가", "나", "다", "라"])

    let outcome = await model.renameEpisodes(
      Set([ids[3], ids[0], ids[2]]), by: .numbered(name: "부", start: 1, numberFirst: true))

    XCTAssertEqual(outcome.renamed, 3)
    XCTAssertEqual(model.episodes.map(\.title), ["1 부", "나", "2 부", "3 부"])
    XCTAssertEqual(try renames(ids[2]).map(\.memo), ["'다' → '2 부' · 3개 회차 함께"])
  }

  /// One ⌘Z reverts all, and undo/redo also leave a snapshot per episode since they change names too.
  func testUndoAndRedoAlsoSnapshot() async throws {
    let (model, ids) = try await makeModel(titles: ["가", "나"])
    let undo = UndoManager()
    undo.groupsByEvent = false

    undo.beginUndoGrouping()
    await model.renameEpisodes([ids[0]: "A", ids[1]: "B"], reason: .batch, undoManager: undo)
    undo.endUndoGrouping()
    XCTAssertEqual(undo.undoActionName, "여러 회차 이름 변경")
    undo.undo()
    try await waitUntil { try self.renames(ids[1]).count == 2 }
    XCTAssertEqual(model.episodes.map(\.title), ["가", "나"])
    undo.redo()
    try await waitUntil { try self.renames(ids[1]).count == 3 }

    XCTAssertEqual(model.episodes.map(\.title), ["A", "B"])
    XCTAssertEqual(try renames(ids[0]).map(\.memo), [
      "'가' → 'A' · 2개 회차 함께", "'A' → '가' · 되돌림", "'가' → 'A' · 다시 실행",
    ])
    XCTAssertEqual(try renames(ids[0]).map(\.title), ["가", "A", "가"], "복원에 쓰는 것은 바뀌기 전 제목")
    try await waitUntil { try self.store.loadProject().episodes.map(\.title) == ["A", "B"] }
  }

  /// For the open episode, the editor's current text (not yet saved) is kept, not the file.
  func testOpenEpisodeUsesEditorText() async throws {
    let (model, ids) = try await makeModel(titles: ["가"])
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "본문 0")
    model.autosaver.attach(textView)
    model.autosaver.begin(episode: ids[0])
    textView.insertText(" 이어 씀", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))

    await model.renameEpisodes([ids[0]: "새 이름"], reason: .single)

    XCTAssertEqual(try renames(ids[0]).map(\.body), ["본문 0 이어 씀"])
    XCTAssertEqual(try renames(ids[0]).map(\.memo), ["'가' → '새 이름'"])
  }

  /// Even with a memo, counted with automatic/leave snapshots toward the keep count and pruned oldest first.
  func testRenameSnapshotsFollowRetention() async throws {
    let (model, ids) = try await makeModel(titles: ["가"])
    model.autosaver.snapshots.settings = .init(retention: 10)

    for round in 0..<12 {
      await model.renameEpisodes([ids[0]: "이름 \(round)"], reason: .single)
    }

    let left = try renames(ids[0])
    XCTAssertEqual(left.count, 10)
    XCTAssertEqual(left.first?.title, "이름 1", "오래된 것부터 지운다")
    let files = try FileManager.default.contentsOfDirectory(atPath: store.layout.snapshotFolder(ids[0]).path(percentEncoded: false))
    XCTAssertEqual(files.filter { $0.hasSuffix(".memo") }.count, 10, "지운 스냅샷의 메모도 함께 지운다")
    XCTAssertEqual(files.filter { $0.hasSuffix(".title") }.count, 10)
  }

  private func waitUntil(_ condition: @escaping () throws -> Bool) async throws {
    for _ in 0..<100 {
      if try condition() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("기다린 상태가 오지 않음")
  }
}
