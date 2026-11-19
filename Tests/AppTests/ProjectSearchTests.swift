import AppKit
import SwiftUI
import NovelCore
import XCTest
@testable import NovelEditor

/// 작품 전체 검색(12단계): 열린 회차의 저장 전 글까지 찾는지, 결과를 누르면 편집기가 그 자리로 가는지.
@MainActor
final class ProjectSearchTests: XCTestCase {
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

  private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      guard ContinuousClock.now < deadline else { return XCTFail("시간 안에 조건이 맞지 않음") }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  /// 방금 친 글(아직 1초 자동 저장 전)도 찾는다. 디스크만 읽으면 못 찾는다.
  func testFindsTextTypedInOpenEpisodeBeforeItIsSaved() async throws {
    let model = ProjectModel(project: try store.loadProject(), store: store, queue: SaveQueue(), autosaveDelay: .seconds(60))
    let first = try await model.addEpisode()
    let second = try await model.addEpisode()
    try store.writeEpisode("검을 들었다", id: first)
    try store.writeEpisode("빈 회차", id: second)
    let textView = ManuscriptTextView.make()
    model.autosaver.attach(textView)
    textView.replaceAllText(with: "빈 회차")
    model.autosaver.begin(episode: second)
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.insertText(" 검이 울었다", replacementRange: NSRange(location: NSNotFound, length: 0))
    let search = ProjectSearch(
      store: store, episodeIDs: { model.episodes.map(\.id) }, texts: { model.autosaver.searchTexts() }, delay: .milliseconds(1))

    search.query = "검"
    search.schedule()

    try await waitUntil { search.result != nil }
    XCTAssertEqual(search.result?.episodes.map(\.id), [first, second])
    XCTAssertEqual(try store.readEpisode(second), "빈 회차", "디스크에는 아직 없다")
  }

  /// 새로 치면 앞 검색을 버리고, 지우면 결과도 사라진다.
  func testNewQueryReplacesResultAndEmptyClears() async throws {
    let id = EpisodeID.make()
    try store.writeEpisode("사과 배 사과", id: id)
    let search = ProjectSearch(store: store, episodeIDs: { [id] }, texts: { [:] }, delay: .milliseconds(1))

    search.query = "사과"
    search.schedule()
    search.query = "배"
    search.schedule()
    try await waitUntil { search.result != nil && !search.isSearching }

    XCTAssertEqual(search.result?.matchCount, 1)
    XCTAssertEqual(search.resultQuery, "배")
    search.query = ""
    search.schedule()
    XCTAssertNil(search.result)
  }

  // MARK: - 결과로 가기

  private func editor(_ text: String) -> (NSWindow, ManuscriptTextView) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let scrollView = NSScrollView(frame: window.contentLayoutRect)
    let textView = ManuscriptTextView.make()
    textView.frame = scrollView.bounds
    scrollView.documentView = textView
    window.contentView = scrollView
    textView.replaceAllText(with: text)
    return (window, textView)
  }

  func testRevealSelectsTheMatch() {
    let (window, textView) = editor("그는 검을 들었다.\n검이 울었다.")
    defer { window.close() }
    let id = EpisodeID.make()

    textView.reveal(TextReveal(episodeID: id, location: 11, length: 1, query: "검", caseSensitive: false))

    XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 1))
  }

  /// 검색한 뒤 앞에 글을 더 써서 자리가 밀렸으면 가장 가까운 같은 문구로 간다.
  func testRevealFindsNearestWhenTextMoved() {
    let (window, textView) = editor("아, 그는 검을 들었다.\n검이 울었다.")
    defer { window.close() }

    // 검색할 때는 "그는 검을…"이 맨 앞이라 둘째 "검"이 11에 있었다. 지금은 앞에 "아, "가 붙어 14에 있다.
    textView.reveal(TextReveal(episodeID: EpisodeID.make(), location: 11, length: 1, query: "검", caseSensitive: false))

    XCTAssertEqual(textView.selectedRange(), NSRange(location: 14, length: 1))
  }

  /// 긴 본문 가운데의 결과로 가면 그 자리가 화면 안에 보인다.
  func testRevealScrollsMatchIntoView() async throws {
    let paragraphs = (1...200).map { "\($0)번째 문단입니다. 그는 길을 걸었다." }
    let target = 150
    var text = paragraphs.joined(separator: "\n\n")
    text = text.replacingOccurrences(of: "\(target)번째", with: "늦었군 \(target)번째")
    let (window, textView) = editor(text)
    defer { window.close() }
    let location = (text as NSString).range(of: "늦었군").location

    textView.reveal(TextReveal(episodeID: EpisodeID.make(), location: location, length: 3, query: "늦었군", caseSensitive: false))
    try await Task.sleep(for: .milliseconds(100))

    let glyphs = textView.layoutManager!.glyphRange(forCharacterRange: NSRange(location: location, length: 3), actualCharacterRange: nil)
    var rect = textView.layoutManager!.boundingRect(forGlyphRange: glyphs, in: textView.textContainer!)
    rect.origin.y += textView.textContainerOrigin.y
    XCTAssertTrue(textView.visibleRect.contains(rect), "보이는 곳 \(textView.visibleRect) 찾은 곳 \(rect)")
  }

  /// 실제 앱처럼: SwiftUI 다리로 다른 회차 본문을 올리면서 같은 갱신에 결과로 가기를 건다.
  func testRevealAfterSwitchingEpisodeShowsMatch() async throws {
    func body(_ mark: Int) -> String {
      (1...130).map { $0 == mark ? "\"늦었군.\"" : "\($0)번째 문단입니다. 그는 길을 걸었다. 바람이 불었다. 하늘은 맑았다." }.joined(separator: "\n\n")
    }
    let first = ManuscriptEditor.Content(token: UUID(), episodeID: EpisodeID.make(), text: body(0))
    let secondText = body(97)
    let second = ManuscriptEditor.Content(token: UUID(), episodeID: EpisodeID.make(), text: secondText)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 846, height: 708), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: ManuscriptEditor(content: first))
    window.contentView = host
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(100))
    let location = (secondText as NSString).range(of: "늦었군").location

    host.rootView = ManuscriptEditor(content: second, reveal: TextReveal(
      episodeID: second.episodeID, location: location, length: 3, query: "늦었군", caseSensitive: false))
    try await Task.sleep(for: .milliseconds(300))

    let textView = try XCTUnwrap((host.subviews.first { $0 is NSScrollView } as? NSScrollView)?.documentView as? ManuscriptTextView
      ?? findTextView(in: host))
    XCTAssertEqual(textView.selectedRange(), NSRange(location: location, length: 3))
    let glyphs = textView.layoutManager!.glyphRange(forCharacterRange: textView.selectedRange(), actualCharacterRange: nil)
    var rect = textView.layoutManager!.boundingRect(forGlyphRange: glyphs, in: textView.textContainer!)
    rect.origin.y += textView.textContainerOrigin.y
    XCTAssertTrue(textView.visibleRect.contains(rect), "보이는 곳 \(textView.visibleRect) 찾은 곳 \(rect) 높이 \(textView.frame.height) max \(textView.maxSize) used \(textView.layoutManager!.usedRect(for: textView.textContainer!)) clip \(String(describing: textView.enclosingScrollView?.contentView.bounds))")
  }

  private func findTextView(in view: NSView) -> ManuscriptTextView? {
    if let textView = view as? ManuscriptTextView { return textView }
    for subview in view.subviews { if let found = findTextView(in: subview) { return found } }
    return nil
  }

  func testRevealDoesNothingWhenPhraseIsGone() {
    let (window, textView) = editor("다 지웠다")
    defer { window.close() }
    textView.setSelectedRange(NSRange(location: 2, length: 0))

    textView.reveal(TextReveal(episodeID: EpisodeID.make(), location: 0, length: 1, query: "검", caseSensitive: false))

    XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
  }
}
