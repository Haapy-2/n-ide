import Foundation
import NovelCore
import XCTest
@testable import NovelEditor

/// 스냅샷 판(11d): 같은 줄 접기, 목록 읽기·최근 것 고르기, 메모 고치기, 날짜 묶음 이름.
@MainActor
final class SnapshotPanelTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!
  private let episode = EpisodeID.make()

  override func setUp() async throws {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    folder = repo.appending(path: "build/tmp/\(UUID().uuidString)")
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "x")
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  // MARK: - 접기

  private func lines(_ count: Int, changeAt changed: Set<Int>) -> (String, String) {
    let old = (0..<count).map { "줄 \($0)" }
    let new = old.enumerated().map { changed.contains($0.offset) ? "고친 줄 \($0.offset)" : $0.element }
    return (old.joined(separator: "\n"), new.joined(separator: "\n"))
  }

  private func shape(_ items: [DiffDisplay.Item]) -> [String] {
    items.map {
      switch $0 {
      case .row(let index, let row): row.isSame ? "=\(index)" : "*\(index)"
      case .folded(let range): "fold\(range.lowerBound)..<\(range.upperBound)"
      }
    }
  }

  func testFoldsLongSameRunsKeepingThreeLinesAroundChanges() throws {
    let (old, new) = lines(30, changeAt: [10, 20])
    let diff = try TextDiff(old: old, new: new)
    let items = DiffDisplay.items(diff.rows)
    // 앞 묶음(0~9)은 뒤 3줄만, 가운데(11~19)는 앞뒤 3줄, 끝(21~29)은 앞 3줄만.
    XCTAssertEqual(shape(items), [
      "fold0..<7", "=7", "=8", "=9", "*10",
      "=11", "=12", "=13", "fold14..<17", "=17", "=18", "=19", "*20",
      "=21", "=22", "=23", "fold24..<30",
    ])
  }

  func testDoesNotFoldSingleHiddenLine() throws {
    // 가운데 같은 줄 7개 = 앞 3 + 숨길 1 + 뒤 3 → 접지 않는다.
    let (old, new) = lines(9, changeAt: [0, 8])
    let items = DiffDisplay.items(try TextDiff(old: old, new: new).rows)
    XCTAssertFalse(items.contains { if case .folded = $0 { true } else { false } })
  }

  func testShortSameRunsBetweenChangesStayOpen() throws {
    // 바뀐 줄 사이의 같은 줄이 1~5개면 앞뒤 3줄이 겹친다. 접지도 죽지도 않아야 한다.
    for gap in 0...6 {
      let (old, new) = lines(gap + 2, changeAt: [0, gap + 1])
      let items = DiffDisplay.items(try TextDiff(old: old, new: new).rows)
      XCTAssertEqual(items.count, gap + 2, "gap \(gap)")
    }
  }

  func testExpandedFoldShowsAllLines() throws {
    let (old, new) = lines(30, changeAt: [10, 20])
    let rows = try TextDiff(old: old, new: new).rows
    let items = DiffDisplay.items(rows, expanded: [14])
    XCTAssertFalse(shape(items).contains("fold14..<17"))
    XCTAssertTrue(shape(items).contains("=15"))
    XCTAssertTrue(shape(items).contains("fold0..<7"))
  }

  func testNoChangesShowsEverythingUnfolded() throws {
    let (old, _) = lines(40, changeAt: [])
    let items = DiffDisplay.items(try TextDiff(old: old, new: old).rows)
    XCTAssertEqual(items.count, 40)
  }

  func testItemIDsAreUnique() throws {
    let (old, new) = lines(60, changeAt: [5, 30, 50])
    let items = DiffDisplay.items(try TextDiff(old: old, new: new).rows)
    XCTAssertEqual(Set(items.map(\.id)).count, items.count)
  }

  // MARK: - 목록과 비교

  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(condition())
  }

  func testLoadsNewestFirstAndComparesIt() async throws {
    let now = Date()
    try store.writeSnapshot("첫 글", episode: episode, kind: .auto, at: now.addingTimeInterval(-120))
    try store.writeSnapshot("둘째 글", episode: episode, kind: .manual, memo: "남길 것", at: now.addingTimeInterval(-60))
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "지금 글")
    await browser.load()
    XCTAssertEqual(browser.items?.map(\.snapshot.kind), [.manual, .auto])
    XCTAssertEqual(browser.items?.first?.memo, "남길 것")
    XCTAssertEqual(browser.selectedID, browser.items?.first?.id)
    try await waitUntil { if case .ready = browser.comparison { true } else { false } }
    guard case .ready(let diff) = browser.comparison else { return }
    XCTAssertEqual(diff.oldLines, ["둘째 글"])
    XCTAssertEqual(diff.newLines, ["지금 글"])
  }

  func testSelectingAnotherSnapshotReplacesComparison() async throws {
    let now = Date()
    try store.writeSnapshot("옛 글", episode: episode, kind: .auto, at: now.addingTimeInterval(-120))
    try store.writeSnapshot("새 글", episode: episode, kind: .auto, at: now.addingTimeInterval(-60))
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "지금")
    await browser.load()
    browser.select(browser.items![1].id)
    try await waitUntil {
      if case .ready(let diff) = browser.comparison { diff.oldLines == ["옛 글"] } else { false }
    }
  }

  func testEmptyEpisodeHasEmptyList() async {
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "")
    await browser.load()
    XCTAssertEqual(browser.items, [])
    XCTAssertEqual(browser.comparison, .idle)
  }

  func testUpdateMemoWritesTrimsAndRemoves() async throws {
    try store.writeSnapshot("글", episode: episode, kind: .auto)
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: "글")
    await browser.load()
    let id = try XCTUnwrap(browser.items?.first?.id)
    browser.updateMemo(id, to: "  다시 볼 것 \n")
    try await waitUntil { browser.items?.first?.memo == "다시 볼 것" }
    XCTAssertEqual(store.readMemo(try store.snapshots(of: episode)[0]), "다시 볼 것")
    browser.updateMemo(id, to: "   ")
    try await waitUntil { browser.items?.first?.memo == nil }
    XCTAssertNil(store.readMemo(try store.snapshots(of: episode)[0]))
    // 본문 스냅샷은 그대로
    XCTAssertEqual(try store.snapshots(of: episode).count, 1)
  }

  // MARK: - 이름

  func testDayTitles() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9))!
    XCTAssertEqual(SnapshotListView.dayTitle(now.addingTimeInterval(-3600), calendar: calendar, now: now), "오늘")
    XCTAssertEqual(SnapshotListView.dayTitle(now.addingTimeInterval(-86_400), calendar: calendar, now: now), "어제")
    XCTAssertNotEqual(SnapshotListView.dayTitle(now.addingTimeInterval(-3 * 86_400), calendar: calendar, now: now), "어제")
  }

  func testEveryKindHasShortName() {
    for kind in SnapshotKind.allCases {
      XCTAssertFalse(SnapshotListView.kindName(kind).isEmpty)
    }
  }

  /// 목록과 비교 칸 제목의 시각은 초까지 보인다.
  func testTimeShowsSeconds() throws {
    let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 14, minute: 23, second: 5)))
    XCTAssertEqual(SnapshotListView.time(date), "14:23:05")
  }
}
