import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

@MainActor
final class StabilityTests: XCTestCase {
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

  private func makeModel() throws -> ProjectModel {
    ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      autosaveDelay: .milliseconds(20), countDelay: .milliseconds(20), countSaveDelay: .seconds(60))
  }

  /// The same project folder gives the same window value whatever shape the path has (trailing `/`, `..`).
  func testSameProjectGetsSameWindowValue() {
    let plain = URL(filePath: "/Users/me/글/작품.novel")
    let slash = URL(filePath: "/Users/me/글/작품.novel/", directoryHint: .isDirectory)
    let dotted = URL(filePath: "/Users/me/글/다른 곳/../작품.novel")
    let value = ProjectLauncher.windowValue(for: plain)
    XCTAssertEqual(ProjectLauncher.windowValue(for: slash), value)
    XCTAssertEqual(ProjectLauncher.windowValue(for: dotted), value)
    XCTAssertEqual(ProjectLauncher.windowValue(for: value), value, "한 번 맞춘 값은 다시 맞춰도 같다")
    XCTAssertNotEqual(ProjectLauncher.windowValue(for: URL(filePath: "/Users/me/글/작품2.novel")), value)
  }

  func testQuitWaitsForProjectSave() async throws {
    let model = try makeModel()
    model.setDefaultEpisodeGoal(3_000)
    XCTAssertTrue(model.autosaver.hasWorkBeforeQuit, "시작한 저장이 남아 있으면 종료를 미룬다")

    await model.autosaver.finish()

    XCTAssertEqual(try store.loadProject().settings.defaultEpisodeGoal, 3_000)
    XCTAssertFalse(model.autosaver.hasWorkBeforeQuit)
  }

  /// Deferred count saves (60 s later here) are written before quit too.
  func testQuitWritesPendingCounts() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    model.recordCount(CharacterCount(withSpaces: 12, withoutSpaces: 10), for: id)
    XCTAssertNil(try store.loadProject().episodes[0].characterCount)
    XCTAssertTrue(model.autosaver.hasWorkBeforeQuit)

    await model.autosaver.finish()

    XCTAssertEqual(try store.loadProject().episodes[0].characterCount, CharacterCount(withSpaces: 12, withoutSpaces: 10))
  }

  /// When a count changes, `project` (the value the whole workspace watches) stays the same; only that episode's box changes.
  func testCountChangeDoesNotTouchProject() async throws {
    let model = try makeModel()
    let id = try await model.addEpisode()
    let other = try await model.addEpisode()
    let before = model.project

    model.recordCount(CharacterCount(withSpaces: 7, withoutSpaces: 6), for: id)

    XCTAssertEqual(model.project, before)
    XCTAssertEqual(model.countBox(for: id).value?.withSpaces, 7)
    XCTAssertNil(model.countBox(for: other).value)
    XCTAssertEqual(model.episode(id)?.characterCount?.withSpaces, 7)
  }

  /// If settings change during composition, the body gets them after composition ends (text storage isn't touched during composition).
  func testStyleChangedDuringCompositionAppliesAfterIt() throws {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "첫 문장")
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(textView.hasMarkedText())

    var style = EditorStyle()
    style.fontSize = 22
    textView.style = style
    XCTAssertTrue(textView.hasMarkedText(), "모양을 바꿔도 조합이 끊기지 않는다")
    XCTAssertEqual(fontSize(of: textView, at: 0), 17, "조합 중에는 본문에 입히지 않는다")

    textView.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertEqual(textView.string, "첫 문장한")
    XCTAssertEqual(fontSize(of: textView, at: 0), 22, "조합이 끝나면 본문 전체에 입힌다")
    XCTAssertEqual(fontSize(of: textView, at: 4), 22)
  }

  private func fontSize(of textView: NSTextView, at index: Int) -> CGFloat? {
    (textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize
  }

  func testSymlinkedPathGetsSameWindowValue() throws {
    let real = folder.appending(path: "작품.novel")
    let link = folder.appending(path: "바로가기.novel")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    XCTAssertEqual(ProjectLauncher.windowValue(for: link), ProjectLauncher.windowValue(for: real))
  }

  /// If the body can't be obtained on leave, "snapshots pending" isn't cleared (it remains as work to await at quit).
  func testLeaveWithoutTextKeepsPendingFlag() throws {
    let snapshotter = EpisodeSnapshotter(store: store)
    snapshotter.settings.autoEnabled = false
    let id = EpisodeID.make()
    snapshotter.noteEdit(id)
    snapshotter.leave(id) { nil }
    XCTAssertTrue(snapshotter.hasPendingWork)
  }
}
