import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// 작업 공간 사이드바(회차 목록·검색 패널)와 여러 회차 이름 변경 창. 실제 창에 띄워 화면에 보이는 것으로 본다.
@MainActor
final class WorkspaceSidebarTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!
  private var windows: [NSWindow] = []
  private var savedCollapsed: Any?
  private var lastVisible = NSRange()

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appending(path: "휴지통"), withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
    savedCollapsed = UserDefaults.standard.object(forKey: AppSettingKey.collapsedEpisodeGroups)
  }

  override func tearDown() async throws {
    for window in windows { window.close() }
    windows = []
    UserDefaults.standard.set(savedCollapsed, forKey: AppSettingKey.collapsedEpisodeGroups)
    try? FileManager.default.removeItem(at: folder)
  }

  private func show(_ view: some View, width: CGFloat = 1100, height: CGFloat = 760) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: view)
    window.makeKeyAndOrderFront(nil)
    windows.append(window)
    return window
  }

  /// 조건이 맞을 때까지 화면 갱신을 돌린다(최대 2초). 맞으면 true.
  @discardableResult
  private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
    for _ in 0..<200 {
      if condition() { return true }
      try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
  }

  private func settle(_ seconds: Double = 0.3) async throws {
    try await Task.sleep(for: .seconds(seconds))
  }

  private func metas(_ count: Int) -> [EpisodeMeta] {
    (1...count).map { EpisodeMeta(title: "\($0)화", goal: 5_000) }
  }

  private func first<T: NSView>(_ type: T.Type, in window: NSWindow) -> T? {
    func find(_ view: NSView) -> T? {
      if let found = view as? T { return found }
      return view.subviews.lazy.compactMap(find).first
    }
    return window.contentView.flatMap(find)
  }

  /// 회차 목록 줄 번호: 0 "회차" 제목, 1 구역 머리, 2부터 보이는 줄(`EpisodeGrouping.rows`).
  private func isVisible(row: Int, in window: NSWindow) throws -> Bool {
    let table = try XCTUnwrap(first(NSTableView.self, in: window))
    let visible = table.rows(in: table.visibleRect)
    lastVisible = visible
    return NSLocationInRange(row + 2, visible)
  }

  // MARK: - 회차 목록

  func testSidebarScrollsToSelectedEpisode() async throws {
    let episodes = metas(500)
    let box = SidebarBox(episodes: episodes, selection: episodes[450].id)
    let window = show(SidebarHost(box: box), width: 300, height: 600)

    try await waitUntil { self.first(NSTableView.self, in: window) != nil }
    try await waitUntil { (try? self.isVisible(row: 450, in: window)) == true }
    XCTAssertTrue(try isVisible(row: 450, in: window), "작품을 열 때 고른 회차가 보인다 \(lastVisible)")

    box.selection = episodes[200].id
    try await waitUntil { (try? self.isVisible(row: 200, in: window)) == true }
    XCTAssertTrue(try isVisible(row: 200, in: window), "다른 회차로 가면(⌥⌘↑, 검색 결과) 그 줄이 보인다 \(lastVisible)")
  }

  func testSelectingEpisodeInsideCollapsedGroupExpandsIt() async throws {
    let part = EpisodeGroup(title: "1부")
    let start = EpisodeGrouping.List(episodes: metas(5), groups: [])
    let list = EpisodeGrouping.group(Set([start.episodes[1].id, start.episodes[2].id]), as: part, in: start)
    UserDefaults.standard.set(part.id.rawValue, forKey: AppSettingKey.collapsedEpisodeGroups)
    let box = SidebarBox(episodes: list.episodes, groups: list.groups, selection: list.episodes[0].id)
    let window = show(SidebarHost(box: box), width: 300, height: 600)
    try await settle()

    box.selection = list.episodes[2].id
    try await waitUntil { UserDefaults.standard.string(forKey: AppSettingKey.collapsedEpisodeGroups) == "" }

    XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingKey.collapsedEpisodeGroups), "", "고른 회차가 든 묶음을 편다")
    // 줄: 0 「1화」, 1 1부, 2 「2화」, 3 「3화」
    try await waitUntil { (try? self.isVisible(row: 3, in: window)) == true }
    XCTAssertTrue(try isVisible(row: 3, in: window))
  }

  /// 휴지통으로 보낸(또는 ⌘Z로 사라진) 회차가 여러 개 고른 목록에 남지 않는다.
  func testListChangeKeepsOnlyRemainingMarkedEpisodes() {
    let ids = (0..<3).map { _ in EpisodeID.make() }
    let after = WorkspaceView.afterListChange(
      selection: ids[0], marked: Set(ids), old: ids, new: [ids[0], ids[2]], whenNothingSelected: { nil })

    XCTAssertEqual(after.selection, ids[0])
    XCTAssertEqual(after.marked, [ids[0], ids[2]])
  }

  func testRestoringEpisodeIntoEmptySelectionSelectsIt() {
    let id = EpisodeID.make()
    let after = WorkspaceView.afterListChange(
      selection: nil, marked: [], old: [], new: [id], whenNothingSelected: { id })

    XCTAssertEqual(after.selection, id)
  }

  /// 마지막 남은 회차를 휴지통으로 보냈다가 ⌘Z로 되살리면 빈 종이가 아니라 그 회차가 열린다.
  func testUndoingTrashOfLastEpisodeOpensIt() async throws {
    let trash = folder.appending(path: "휴지통")
    let model = ProjectModel(
      project: try store.loadProject(), store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]),
      moveToTrash: { url in
        let destination = trash.appending(path: url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
      })
    let id = try await model.addEpisode()
    _ = show(WorkspaceView(model: model))
    try await waitUntil { model.autosaver.episodeID == id }
    XCTAssertEqual(model.autosaver.episodeID, id)

    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    try await model.trashEpisode(id, undoManager: undo)
    undo.endUndoGrouping()
    try await settle()
    undo.undo()
    await model.finishFileUndos()
    XCTAssertEqual(model.episodes.map(\.id), [id])

    try await waitUntil { model.autosaver.episodeID == id }
    XCTAssertEqual(model.autosaver.episodeID, id, "되살린 회차가 편집기에 열린다")
  }

  // MARK: - 검색 패널

  private func makeSearch(_ box: SearchBox) -> (ProjectSearch, ProjectReplace) {
    let store = store!
    let autosaver = EpisodeAutosaver(store: store, queue: SaveQueue(retryDelays: [.milliseconds(5)]), delay: .seconds(60))
    let search = ProjectSearch(store: store, episodeIDs: { box.episodes.map(\.id) }, texts: { [:] }, delay: .zero)
    let replace = ProjectReplace(store: store, autosaver: autosaver, episodeIDs: { box.episodes.map(\.id) }, recordCount: { _, _ in })
    return (search, replace)
  }

  /// 검색 결과가 휴지통으로 간 회차를 가리키지 않고, ⌘Z로 되살리면 다시 찾는다.
  func testSearchResultsFollowEpisodeListChanges() async throws {
    let episodes = metas(2)
    for episode in episodes { try store.writeEpisode("달빛 아래", id: episode.id) }
    let box = SearchBox(episodes: episodes)
    let (search, replace) = makeSearch(box)
    search.query = "달빛"
    _ = show(SearchHost(box: box, search: search, replace: replace), width: 300, height: 600)
    try await waitUntil { search.result?.episodes.count == 2 }
    XCTAssertEqual(search.result?.episodes.count, 2)

    box.episodes = [episodes[0]]
    try await waitUntil { search.result?.episodes.map(\.id) == [episodes[0].id] }
    XCTAssertEqual(search.result?.episodes.map(\.id), [episodes[0].id], "지운 회차는 결과에서 빠진다")

    box.episodes = episodes
    try await waitUntil { search.result?.episodes.count == 2 }
    XCTAssertEqual(search.result?.episodes.map(\.id), episodes.map(\.id), "되살린 회차는 다시 찾는다")
  }

  // MARK: - 여러 회차 이름 변경 창

  /// 엔터를 빠르게 두 번 눌러도 규칙은 한 번만 적용된다.
  func testBatchRenameAppliesOnceOnDoubleReturn() async throws {
    let episodes = metas(2)
    var applied = 0
    let window = show(
      BatchRenameSheet(episodes: episodes, targetIDs: Set(episodes.map(\.id)), onCancel: {}, onRename: { _ in applied += 1 }),
      width: 540, height: 520)
    try await settle()
    for _ in 0..<6 where (window.firstResponder as? NSTextView)?.isFieldEditor != true { window.selectNextKeyView(nil) }
    let fieldEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
    XCTAssertTrue(fieldEditor.isFieldEditor)
    fieldEditor.insertText("화", replacementRange: fieldEditor.selectedRange())
    try await settle()

    let enter = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    window.performKeyEquivalent(with: enter)
    window.performKeyEquivalent(with: enter)
    try await settle()

    XCTAssertEqual(applied, 1)
  }
}

@MainActor
@Observable
private final class SidebarBox {
  var episodes: [EpisodeMeta]
  var groups: [EpisodeGroup]
  var selection: EpisodeID?
  var marked: Set<EpisodeID> = []

  init(episodes: [EpisodeMeta], groups: [EpisodeGroup] = [], selection: EpisodeID?) {
    self.episodes = episodes
    self.groups = groups
    self.selection = selection
  }
}

/// 작업 공간이 회차 목록을 띄우는 짜임. 선택을 밖에서 바꿀 수 있게 따로 꾸렸다(MemoryGrowthTests.SwitchHost와 같은 까닭).
private struct SidebarHost: View {
  @Bindable var box: SidebarBox
  @State private var inset: CGFloat?

  var body: some View {
    EpisodeList(
      episodes: box.episodes, groups: box.groups, selection: $box.selection, marked: $box.marked,
      measuredInset: $inset)
  }
}

@MainActor
@Observable
private final class SearchBox {
  var episodes: [EpisodeMeta]
  init(episodes: [EpisodeMeta]) { self.episodes = episodes }
}

private struct SearchHost: View {
  let box: SearchBox
  let search: ProjectSearch
  let replace: ProjectReplace
  @State private var inset: CGFloat?

  var body: some View {
    SearchPanel(
      search: search, replace: replace, episodes: box.episodes, focusRequest: 0, measuredInset: $inset,
      onReveal: { _ in }, onReplaced: { _ in }, onShowReplaced: { _ in }, onClose: {})
  }
}
