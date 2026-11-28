import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

/// Episode groups (PLAN ch.8). Grouping never touches body files.
@MainActor
final class EpisodeGroupTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeModel(episodes count: Int) async throws -> (ProjectModel, [EpisodeID]) {
    let model = ProjectModel(project: try store.loadProject(), store: store, queue: SaveQueue())
    var ids: [EpisodeID] = []
    for index in 0..<count {
      let id = try await model.addEpisode()
      try store.writeEpisode("본문 \(index + 1)", id: id)
      ids.append(id)
    }
    return (model, ids)
  }

  private func undoManager() -> UndoManager {
    let undo = UndoManager()
    undo.groupsByEvent = false
    return undo
  }

  func testGroupingIsSavedAndUndoRestoresOrderAndGroups() async throws {
    let (model, ids) = try await makeModel(episodes: 5)
    let undo = undoManager()

    undo.beginUndoGrouping()
    let made = await model.groupEpisodes([ids[1], ids[4]], title: "  1부 귀환 ", undoManager: undo)
    let group = try XCTUnwrap(made)
    undo.endUndoGrouping()

    let saved = try store.loadProject()
    XCTAssertEqual(saved.groups.map(\.title), ["1부 귀환"])
    XCTAssertEqual(saved.episodes.map(\.id), [ids[0], ids[1], ids[4], ids[2], ids[3]])
    XCTAssertEqual(saved.episodes.filter { $0.group == group }.map(\.id), [ids[1], ids[4]])

    undo.undo()
    await model.finishProjectSaves()
    XCTAssertEqual(model.episodes.map(\.id), ids)
    XCTAssertTrue(model.project.groups.isEmpty)
    XCTAssertEqual(try store.loadProject().episodes.map(\.id), ids)
    // Body files unchanged
    XCTAssertEqual(try store.readEpisode(ids[4]), "본문 5")
  }

  func testNewEpisodeAfterGroupedOneJoinsTheGroup() async throws {
    let (model, ids) = try await makeModel(episodes: 3)
    let made = await model.groupEpisodes([ids[0], ids[1]], title: "1부")
    let group = try XCTUnwrap(made)

    let added = try await model.addEpisode(after: ids[1])

    XCTAssertEqual(model.episode(added)?.group, group)
    XCTAssertEqual(model.episodes.map(\.id), [ids[0], ids[1], added, ids[2]])
  }

  func testDraggingIntoGroupJoinsAndOutLeaves() async throws {
    let (model, ids) = try await makeModel(episodes: 4)
    let made = await model.groupEpisodes([ids[0], ids[1]], title: "1부")
    let group = try XCTUnwrap(made)

    // Episode 4 between 1 and 2 (rows: 0 1부, 1 「1」, 2 「2」, 3 「3」, 4 「4」)
    await model.moveEpisodes(rows: [4], before: 2)
    XCTAssertEqual(model.episodes.filter { $0.group == group }.map(\.id), [ids[0], ids[3], ids[1]])

    // Episode 1 to the very end (rows: 0 1부, 1 「1」, 2 「4」, 3 「2」, 4 「3」)
    await model.moveEpisodes(rows: [1], before: 5)
    XCTAssertNil(model.episode(ids[0])?.group)
    XCTAssertEqual(model.episodes.last?.id, ids[0])
  }

  func testRenameAndUngroup() async throws {
    let (model, ids) = try await makeModel(episodes: 2)
    let made = await model.groupEpisodes(Set(ids), title: "1부")
    let group = try XCTUnwrap(made)

    await model.renameGroup(group, to: "1부 귀환")
    XCTAssertEqual(try store.loadProject().groups.first?.title, "1부 귀환")

    await model.ungroup(group)
    XCTAssertTrue(try store.loadProject().groups.isEmpty)
    XCTAssertEqual(model.episodes.map(\.id), ids)
  }
}
