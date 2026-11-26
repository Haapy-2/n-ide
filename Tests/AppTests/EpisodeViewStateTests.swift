import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// 회차를 다시 열 때 커서와 화면 위치로 돌아간다.
@MainActor
final class EpisodeViewStateTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suite = "EpisodeViewStateTests"

  override func setUp() {
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
  }

  func testRemembersAcrossLaunches() {
    let id = EpisodeID.make()
    let state = EpisodeViewState(caret: 120, top: 80, openedAt: Date(timeIntervalSince1970: 100))
    EpisodeViewStates(defaults: defaults).record(state, for: id)
    XCTAssertEqual(EpisodeViewStates(defaults: defaults).state(for: id), state)
  }

  func testKeepsOnlyRecentEpisodes() {
    let states = EpisodeViewStates(defaults: defaults, limit: 2)
    let ids = (0..<3).map { _ in EpisodeID.make() }
    for (index, id) in ids.enumerated() {
      states.record(EpisodeViewState(caret: 0, top: 0, openedAt: Date(timeIntervalSince1970: Double(index))), for: id)
    }
    XCTAssertNil(states.state(for: ids[0]), "가장 오래 안 연 회차부터 지운다")
    XCTAssertNotNil(states.state(for: ids[2]))
  }

  func testLastOpenedAmongThisProject() {
    let states = EpisodeViewStates(defaults: defaults)
    let a = EpisodeID.make(), b = EpisodeID.make(), other = EpisodeID.make()
    states.record(EpisodeViewState(caret: 0, top: 0, openedAt: Date(timeIntervalSince1970: 10)), for: a)
    states.record(EpisodeViewState(caret: 0, top: 0, openedAt: Date(timeIntervalSince1970: 20)), for: b)
    states.record(EpisodeViewState(caret: 0, top: 0, openedAt: Date(timeIntervalSince1970: 30)), for: other)
    XCTAssertEqual(states.lastOpened(among: [a, b]), b, "다른 작품의 회차는 보지 않는다")
    XCTAssertNil(states.lastOpened(among: [EpisodeID.make()]))
  }

  /// 편집기에서 커서와 화면 맨 위 글자를 읽고, 다른 본문을 거쳐 돌아왔을 때 그 자리로 간다.
  func testEditorReturnsToCaretAndScroll() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let scroll = NSScrollView(frame: window.contentLayoutRect)
    let textView = ManuscriptTextView.make()
    scroll.documentView = textView
    window.contentView = scroll
    textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    let long = (1...400).map { "\($0)번째 문단입니다. 이어지는 글이 조금 더 있습니다." }.joined(separator: "\n")
    textView.replaceAllText(with: long)
    let target = (long as NSString).range(of: "300번째").location
    textView.restoreViewState(EpisodeViewState(caret: target + 2, top: target, openedAt: Date()))

    let saved = textView.viewState()
    XCTAssertEqual(saved.caret, target + 2)
    XCTAssertGreaterThan(saved.top, (long as NSString).range(of: "290번째").location, "화면이 300번째 문단 근처에 있다")
    XCTAssertLessThanOrEqual(saved.top, target)

    textView.replaceAllText(with: "짧은 다른 회차")
    textView.replaceAllText(with: long)
    textView.restoreViewState(saved)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: target + 2, length: 0))
    XCTAssertEqual(textView.viewState().top, saved.top)
  }

  /// 회차를 연 직후 한 차례 늦게 자리를 다시 맞출 때, 그사이 조합이 시작됐으면 선택을 옮기지 않는다.
  func testLateRestoreLeavesCompositionAlone() async throws {
    let id = EpisodeID.make()
    EpisodeViewStates.shared.record(EpisodeViewState(caret: 3, top: 0, openedAt: Date()), for: id)
    let content = ManuscriptEditor.Content(token: UUID(), episodeID: id, text: "가나다라마")
    var editor: ManuscriptTextView?
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = NSHostingView(rootView: ManuscriptEditor(content: content, onReady: { textView in
      editor = textView
      // 편집기가 본문을 넣은 뒤 늦은 자리 맞추기보다 먼저 오는 첫 키
      DispatchQueue.main.async { [weak textView] in
        textView?.setMarkedText(
          "ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
      }
    }))
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(100))
    let textView = try XCTUnwrap(editor)

    XCTAssertEqual(textView.string, "가나다ㄱ라마")
    XCTAssertTrue(textView.hasMarkedText())
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
  }

  /// 기억한 커서가 한 글자(이모지) 가운데면 그 글자 앞으로.
  func testRestoreKeepsCaretOffEmojiMiddle() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "가👍나")
    textView.restoreViewState(EpisodeViewState(caret: 2, top: 0, openedAt: Date()))
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
  }

  func testRestoreClampsToShorterText() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "짧다")
    textView.restoreViewState(EpisodeViewState(caret: 999, top: 999, openedAt: Date()))
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
  }
}
