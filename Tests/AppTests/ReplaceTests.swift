import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 작품 전체 바꾸기 실행(PLAN 14장 2번). 바꾸기 전 글을 잃지 않는지, 바꾸면 안 되는 회차를 건너뛰는지를 본다.
@MainActor
final class ReplaceTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!
  private var model: ProjectModel!
  private var textView: ManuscriptTextView!
  private var replace: ProjectReplace!
  private var open: EpisodeID!
  private var closed: EpisodeID!
  private var untouched: EpisodeID!
  /// nil이 아니면 바꾸는 쪽이 보는 회차 목록을 이것으로 바꾼다(센 뒤 휴지통으로 간 회차 흉내).
  private var listedIDs: [EpisodeID]?

  private var autosaver: EpisodeAutosaver { model.autosaver }

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
    model = ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      autosaveDelay: .seconds(60))
    open = try await model.addEpisode()
    closed = try await model.addEpisode()
    untouched = try await model.addEpisode()
    try store.writeEpisode("민준이 웃었다", id: open)
    try store.writeEpisode("민준과 민준", id: closed)
    try store.writeEpisode("아무도 없다", id: untouched)

    textView = ManuscriptTextView.make()
    autosaver.attach(textView)
    show(open)
    let model = model!
    replace = ProjectReplace(
      store: store, autosaver: autosaver, episodeIDs: { [unowned self] in listedIDs ?? model.episodes.map(\.id) },
      recordCount: { model.recordCount($0, for: $1) })
  }

  override func tearDown() async throws {
    for path in [store.layout.episodesFolder, store.layout.snapshotFolder(closed)] {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path(percentEncoded: false))
    }
    try? FileManager.default.removeItem(at: folder)
  }

  /// 편집기에 회차를 올린다(작업 공간이 회차를 옮길 때와 같은 순서).
  private func show(_ id: EpisodeID) {
    autosaver.leaveEpisode()
    if let pending = autosaver.pendingText(for: id) {
      textView.replaceAllText(with: pending)
      autosaver.begin(episode: id)
    } else {
      let version = try! store.readEpisodeVersion(id)
      textView.replaceAllText(with: version.text)
      autosaver.begin(episode: id, version: version)
    }
  }

  private func type(_ text: String) {
    textView.insertText(text, replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
    autosaver.textDidChange()
  }

  /// 센 뒤 확인 창이 보여 줄 것까지
  private func prepare(_ query: String, _ replacement: String) async throws -> ProjectReplace.Pending {
    replace.replacement = replacement
    await replace.prepare(query: query, caseSensitive: false)
    return try XCTUnwrap(replace.pending)
  }

  private func replaceAll(_ query: String, _ replacement: String) async throws -> ProjectReplace.Report {
    try await run(try await prepare(query, replacement))
  }

  private func run(_ pending: ProjectReplace.Pending) async throws -> ProjectReplace.Report {
    let report = await replace.confirm(pending)
    return try XCTUnwrap(report)
  }

  /// 바깥에서 파일을 고친다. 수정 시각이 같게 찍히지 않게 1초 뒤로 맞춘다.
  private func writeOutside(_ text: String, to id: EpisodeID) throws {
    let url = store.layout.episodeFile(id)
    let before = FileStamp(of: url)?.modified ?? Date()
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: before.addingTimeInterval(1)], ofItemAtPath: url.path(percentEncoded: false))
  }

  func testCountsEveryPlaceBeforeAsking() async throws {
    let pending = try await prepare("민준", "도윤")
    XCTAssertEqual(pending.plan.episodes.map(\.id), [open, closed])
    XCTAssertEqual(pending.title, "2개 회차에서 3곳을 '도윤'(으)로 바꿀까요?")
    XCTAssertEqual(try store.readEpisode(closed), "민준과 민준", "묻기 전에는 바꾸지 않는다")
  }

  func testReplacesOpenAndClosedEpisodes() async throws {
    let report = try await replaceAll("민준", "도윤")

    XCTAssertEqual(report.replaced.map(\.id), [closed, open], "열린 회차는 맨 끝에")
    XCTAssertEqual(report.replaced.map(\.count), [2, 1])
    XCTAssertEqual(report.count, 3)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(ProjectReplace.summary(of: report), "3곳을 바꿨어요")
    XCTAssertEqual(textView.string, "도윤이 웃었다")
    XCTAssertEqual(try store.readEpisode(closed), "도윤과 도윤")
    XCTAssertEqual(try store.readEpisode(untouched), "아무도 없다")
    XCTAssertEqual(model.countBox(for: closed).value, CharacterCount(counting: "도윤과 도윤"))

    await autosaver.flush()
    XCTAssertEqual(try store.readEpisode(open), "도윤이 웃었다", "열린 회차는 평소 자동 저장이 쓴다")
    XCTAssertFalse(autosaver.hasUnsavedChanges)
  }

  /// 회차마다 바꾸기 전·바꾼 뒤를 짝으로, 한 번의 바꾸기는 모두 같은 시각, 메모는 저절로.
  func testLeavesBeforeAndAfterSnapshotsWithMemo() async throws {
    let report = try await replaceAll("민준", "도윤")

    let cases: [(EpisodeID, String, String, Int)] = [(open, "민준이 웃었다", "도윤이 웃었다", 1), (closed, "민준과 민준", "도윤과 도윤", 2)]
    for (id, before, after, count) in cases {
      let snapshots = try store.snapshots(of: id)
      XCTAssertEqual(snapshots.map(\.kind), [.replace, .replaced])
      XCTAssertEqual(try store.readSnapshot(snapshots[0]), before)
      XCTAssertEqual(try store.readSnapshot(snapshots[1]), after)
      XCTAssertEqual(store.readMemo(snapshots[0]), "'민준' → '도윤' 전체 바꾸기 · 바꾸기 전 · \(count)곳")
      XCTAssertEqual(store.readMemo(snapshots[1]), "'민준' → '도윤' 전체 바꾸기 · 바꾼 뒤 · \(count)곳")
      let entry = report.replaced.first { $0.id == id }
      XCTAssertEqual(entry?.before, snapshots[0])
      XCTAssertEqual(entry?.after, snapshots[1])
    }
    XCTAssertEqual(Set(report.replaced.compactMap { $0.before?.date }).count, 1, "모든 회차가 같은 시각")
    XCTAssertEqual(try store.snapshots(of: untouched), [])
  }

  /// 검색 패널의 바꾼 회차 목록: 회차 순서대로(바꾼 차례와 달리 열린 회차가 끝이 아님), 검색어를 고치면 비운다.
  func testFinishedListsReplacedEpisodesInEpisodeOrder() async throws {
    let report = try await replaceAll("민준", "도윤")

    XCTAssertEqual(report.replaced.map(\.id), [closed, open])
    let finished = try XCTUnwrap(replace.finished)
    XCTAssertEqual(finished.replaced.map(\.id), [open, closed])
    XCTAssertEqual(finished.replaced.map(\.count), [1, 2])
    XCTAssertEqual(finished.query, "민준")
    XCTAssertEqual(finished.replacement, "도윤")
    XCTAssertEqual(finished.replaced.first?.before?.kind, .replace)
    replace.clearFinished()
    XCTAssertNil(replace.finished)
  }

  func testCancelLeavesNoSnapshot() async throws {
    _ = try await prepare("민준", "도윤")
    replace.cancel()
    XCTAssertNil(replace.pending)
    XCTAssertEqual(try store.snapshots(of: closed), [])
  }

  func testEmptyReplacementDeletes() async throws {
    let pending = try await prepare("민준", "")
    XCTAssertEqual(pending.title, "2개 회차에서 '민준' 3곳을 지울까요?")
    _ = try await run(pending)
    XCTAssertEqual(try store.readEpisode(closed), "과 ")
    XCTAssertEqual(store.readMemo(try store.snapshots(of: closed)[0]), "'민준' 모두 지우기 · 바꾸기 전 · 2곳")
  }

  func testUndoInEditorReturnsOpenEpisodeInOneStep() async throws {
    _ = try await replaceAll("민준", "도윤")
    textView.undo(nil)
    XCTAssertEqual(textView.string, "민준이 웃었다")
    textView.redo(nil)
    XCTAssertEqual(textView.string, "도윤이 웃었다")
  }

  func testReplacesTextThatFailedToSave() async throws {
    show(closed)
    type(" 민준")
    let episodes = store.layout.episodesFolder.path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: episodes)
    await autosaver.flush()
    show(open)
    XCTAssertEqual(autosaver.pendingText(for: closed), "민준과 민준 민준")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: episodes)

    let report = try await replaceAll("민준", "도윤")

    XCTAssertEqual(report.replaced.first { $0.id == closed }?.count, 3, "메모리에 남은 글에서 바꾼다")
    XCTAssertEqual(try store.readEpisode(closed), "도윤과 도윤 도윤")
    XCTAssertNil(autosaver.pendingText(for: closed))
    let before = try XCTUnwrap(try store.snapshots(of: closed).first { $0.kind == .replace })
    XCTAssertEqual(try store.readSnapshot(before), "민준과 민준 민준")
  }

  func testWriteFailureKeepsReplacedTextInMemory() async throws {
    let pending = try await prepare("민준", "도윤")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: store.layout.episodesFolder.path(percentEncoded: false))

    let report = try await run(pending)

    XCTAssertEqual(report.replaced.map(\.id), [closed, open])
    XCTAssertEqual(try store.readEpisode(closed), "민준과 민준")
    XCTAssertEqual(autosaver.pendingText(for: closed), "도윤과 도윤", "쓰지 못한 글은 저장 실패처럼 붙잡는다")
    guard case .failed = autosaver.status else { return XCTFail("상태 줄이 실패를 알려야 한다") }
  }

  /// 센 뒤 앱 밖에서 바뀌었으면 바뀐 글에서 바꾼다. 바깥에서 고친 글도 지켜진다.
  func testReplacesInTextChangedOutsideAfterCounting() async throws {
    let pending = try await prepare("민준", "도윤")
    try writeOutside("민준이 바깥에서 고침", to: closed)

    let report = try await run(pending)

    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(report.replaced.first { $0.id == closed }?.count, 1)
    XCTAssertEqual(try store.readEpisode(closed), "도윤이 바깥에서 고침")
    XCTAssertTrue(autosaver.conflicts.isEmpty, "고친 적 없는 회차라 묻지 않는다")
    XCTAssertEqual(try store.readSnapshot(try store.snapshots(of: closed)[0]), "민준이 바깥에서 고침")
  }

  func testSkipsEpisodeWaitingForConflictChoice() async throws {
    type(" 더")
    try writeOutside("바깥 글", to: open)
    await autosaver.checkExternalChange()
    XCTAssertNotNil(autosaver.conflicts[open])

    let report = try await replaceAll("민준", "도윤")

    XCTAssertEqual(report.conflicted, 1)
    XCTAssertEqual(ProjectReplace.summary(of: report), "2곳을 바꿨어요 · 1개 회차는 건너뛰었어요")
    XCTAssertEqual(textView.string, "민준이 웃었다 더")
    XCTAssertEqual(try store.readEpisode(closed), "도윤과 도윤")
  }

  /// 확인 창이 떠 있는 동안 친 글도 바꾼다.
  func testIncludesTextTypedWhileAsking() async throws {
    let pending = try await prepare("민준", "도윤")
    type(" 민준")

    let report = try await run(pending)

    XCTAssertEqual(report.replaced.last?.count, 2)
    XCTAssertEqual(textView.string, "도윤이 웃었다 도윤")
  }

  func testIgnoresEpisodeTrashedAfterCounting() async throws {
    let pending = try await prepare("민준", "도윤")
    listedIDs = [open, untouched]
    try FileManager.default.removeItem(at: store.layout.episodeFile(closed))

    let report = try await run(pending)

    XCTAssertEqual(report.skipped, 0, "작가가 지운 회차라 건너뜀으로 세지 않는다")
    XCTAssertEqual(report.replaced.map(\.id), [open])
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: store.layout.episodeFile(closed).path(percentEncoded: false)),
      "지운 회차의 본문 파일을 되살리지 않는다")
  }

  /// 바꾸는 도중(스냅샷을 쓰는 사이) 휴지통으로 간 회차에는 쓰지 않는다. 쓰면 지운 회차 파일이 되살아난다.
  func testDoesNotWriteEpisodeThatLeftTheList() async throws {
    autosaver.isListed = { [closed] in $0 != closed }
    let outcome = await autosaver.replace(
      closed, .init(query: "민준", replacement: "도윤", caseSensitive: false, date: Date(), memo: "메모"))

    XCTAssertEqual(outcome, .nothing)
    XCTAssertEqual(try store.readEpisode(closed), "민준과 민준")
  }

  func testSnapshotFailureLeavesEpisodeUnchanged() async throws {
    let snapshotFolder = store.layout.snapshotFolder(closed)
    try FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: snapshotFolder.path(percentEncoded: false))

    let report = try await replaceAll("민준", "도윤")

    XCTAssertEqual(report.snapshotFailed, 1)
    XCTAssertEqual(try store.readEpisode(closed), "민준과 민준")
    XCTAssertEqual(textView.string, "도윤이 웃었다", "다른 회차는 바꾼다")
  }

  /// 조합 중이면 끊지 않고 기다렸다가, 조합이 끝난 뒤 바꾼다. 조합하던 글자는 그대로 들어간다.
  func testWaitsForCompositionToEnd() async throws {
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    let pending = try await prepare("민준", "도윤")

    let running = Task { try await run(pending) }
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(textView.hasMarkedText(), "조합을 끊지 않는다")
    XCTAssertEqual(textView.string, "민준이 웃었다ㅎ")
    XCTAssertEqual(try store.readEpisode(closed), "도윤과 도윤", "다른 회차는 먼저 끝난다")

    textView.insertText("하", replacementRange: NSRange(location: NSNotFound, length: 0))
    _ = try await running.value

    XCTAssertEqual(textView.string, "도윤이 웃었다하")
  }

  /// 찾은 자리만 바꾸므로 커서는 같은 글자 앞에, 화면 맨 위 줄도 그대로다.
  func testKeepsCaretAndScrollPosition() async throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let scrollView = NSScrollView(frame: window.contentLayoutRect)
    textView.frame = scrollView.bounds
    scrollView.documentView = textView
    window.contentView = scrollView
    let text = (1...200).map { "민준이 \($0)번째 줄에서 걸었다." }.joined(separator: "\n")
    _ = textView.replaceAllUndoably(with: text, actionName: "준비")
    let caret = (text as NSString).range(of: "150번째").location
    textView.restoreViewState(EpisodeViewState(caret: caret, top: (text as NSString).range(of: "민준이 100번째").location, openedAt: Date()))
    XCTAssertGreaterThan(textView.viewState().top, 1_000, "가운데쯤 보고 있다")
    let topLine = (textView.string as NSString).substring(with: NSRange(location: textView.viewState().top, length: 8))

    _ = try await replaceAll("민준", "도윤이라는 사람")

    let after = textView.string as NSString
    XCTAssertTrue(after.substring(from: textView.selectedRange().location).hasPrefix("150번째"), "커서는 같은 글자 앞")
    XCTAssertEqual(
      after.substring(with: NSRange(location: textView.viewState().top, length: 14)),
      topLine.replacingOccurrences(of: "민준", with: "도윤이라는 사람").prefix(14).description, "화면 맨 위 줄 그대로")
  }
}
