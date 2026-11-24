import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 같은 말 여러 커서(⌘D, PLAN 16장). 입력기 호출은 16장 5번 실험에서 본 순서 그대로 재생한다.
@MainActor
final class MultiCursorEditingTests: XCTestCase {
  private var view: ManuscriptTextView!
  private let none = NSRange(location: NSNotFound, length: 0)

  private var undo: UndoManager { view.episodeUndoManager }

  override func setUp() async throws {
    view = ManuscriptTextView.make()
    view.replaceAllText(with: "민준 가 민준 나 민준")
    // 테스트에는 이벤트가 없어 실행 취소 묶음이 저절로 닫히지 않는다. 키 하나를 묶음 하나로 직접 닫는다.
    undo.groupsByEvent = false
  }

  private func key(_ body: () -> Void) {
    undo.beginUndoGrouping()
    body()
    undo.endUndoGrouping()
  }

  /// 맨 앞 커서 앞 `count`글자(입력기가 "앞 글자를 이 글로" 바꿀 때 주는 범위)
  private func beforeCaret(_ count: Int) -> NSRange {
    NSRange(location: view.selectedRange().location - count, length: count)
  }

  private func selectThree() {
    view.setSelectedRange(NSRange(location: 0, length: 2))
    view.selectNextOccurrence(nil)
    view.selectNextOccurrence(nil)
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [0, 5, 10])
  }

  /// 표시된 글자 없이 조합하는 두벌식(16장 5번 ⓐ): ㄷ → 도 → 동 → 도 + 유 → 윤.
  /// 같은 글자를 고치는 키는 기록을 늘리기만 해 묶음을 열지 않는다(실제 앱도 기록이 생길 때만 묶음이 열린다).
  /// 그 키가 몰래 기록을 남기면 열린 묶음이 없어 예외로 드러난다.
  private func typeDoyunReplacing() {
    key { view.insertText("ㄷ", replacementRange: none) }
    view.insertText("도", replacementRange: beforeCaret(1))
    view.insertText("동", replacementRange: beforeCaret(1))
    key {
      view.insertText("도", replacementRange: beforeCaret(1))
      view.insertText("유", replacementRange: none)
    }
    view.insertText("윤", replacementRange: beforeCaret(1))
  }

  // MARK: - ⌘D

  func testCaretSelectsWordFirstThenAddsWholeWordMatches() {
    view.replaceAllText(with: "민준이 민준이가 민준이")
    view.setSelectedRange(NSRange(location: 1, length: 0))

    view.selectNextOccurrence(nil)
    XCTAssertNil(view.multiCursorRanges, "처음 ⌘D는 단어만 고른다")
    XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "민준이")

    view.selectNextOccurrence(nil)
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [0, 9], "'민준이가'는 단어 전체가 아니라 건너뛴다")
    XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 3), "입력기와 이어진 선택은 맨 앞 자리")
  }

  func testSingleMatchStaysOneCursor() {
    view.replaceAllText(with: "민준 가")
    view.setSelectedRange(NSRange(location: 0, length: 2))

    view.selectNextOccurrence(nil)

    XCTAssertNil(view.multiCursorRanges)
  }

  // MARK: - 한글 입력

  func testReplacementModeHangulGoesToEveryCursor() {
    selectThree()

    typeDoyunReplacing()

    XCTAssertEqual(view.string, "도윤 가 도윤 나 도윤")
    XCTAssertEqual(view.multiCursorRanges, [2, 7, 12].map { NSRange(location: $0, length: 0) })
    XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0))
    XCTAssertFalse(view.hasMarkedText())
  }

  /// 표시된 글자 방식(16장 5번 ⓑ). 조합 중에는 모든 자리가 조합 중이고, 입력기에는 맨 앞 자리의 조합 범위를 알린다.
  func testMarkedModeHangulGoesToEveryCursor() {
    selectThree()

    key { view.setMarkedText("ㄷ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none) }
    XCTAssertTrue(view.hasMarkedText())
    XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 1))
    XCTAssertEqual(view.string, "ㄷ 가 ㄷ 나 ㄷ")
    view.setMarkedText("도", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
    view.setMarkedText("동", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
    key {
      view.insertText("도", replacementRange: none)
      view.setMarkedText("유", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
    }
    XCTAssertEqual(view.markedRange(), NSRange(location: 1, length: 1))
    view.setMarkedText("윤", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
    key {
      view.insertText("윤", replacementRange: none)
      view.insertText(" ", replacementRange: none)
    }

    XCTAssertEqual(view.string, "도윤  가 도윤  나 도윤 ")
    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(view.multiCursorRanges?.count, 3)
  }

  func testDeleteBackwardAndNewlineAtEveryCursor() {
    selectThree()
    key { view.insertText("가", replacementRange: none) }

    key { view.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }
    XCTAssertEqual(view.string, " 가  나 ")
    key { view.doCommand(by: #selector(NSResponder.insertNewline(_:))) }

    XCTAssertEqual(view.string, "\n 가 \n 나 \n")
    XCTAssertEqual(view.multiCursorRanges?.count, 3)
  }

  /// 지우다 커서가 만나면 하나가 된다. 하나만 남으면 보통 편집기로.
  func testCursorsThatMeetBecomeOne() {
    view.replaceAllText(with: "가가")
    view.setSelectedRange(NSRange(location: 0, length: 1))
    view.selectNextOccurrence(nil)

    key { view.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }

    XCTAssertEqual(view.string, "")
    XCTAssertNil(view.multiCursorRanges)
  }

  // MARK: - 실행 취소

  /// 조합 하나(한 글자)가 모든 자리에서 ⌘Z 한 단위(16장 U1). 되돌리면 그때의 커서들로(U2).
  func testUndoTakesOneComposedCharacterAtEveryCursor() {
    selectThree()
    typeDoyunReplacing()

    view.undo(nil)
    XCTAssertEqual(view.string, "도 가 도 나 도")
    XCTAssertEqual(view.multiCursorRanges, [1, 5, 9].map { NSRange(location: $0, length: 0) })

    view.undo(nil)
    XCTAssertEqual(view.string, "민준 가 민준 나 민준")
    XCTAssertEqual(view.multiCursorRanges, [0, 5, 10].map { NSRange(location: $0, length: 2) }, "고른 말로 돌아온다")

    view.redo(nil)
    XCTAssertEqual(view.string, "도 가 도 나 도")
  }

  // MARK: - 다른 길과 부딪힘

  /// 본문을 통째로 바꾸는 길(회차 전환, 외부 변경, 스냅샷 복원)과 프로그램이 옮긴 선택은 여러 커서를 끝낸다(16장 D3).
  func testWholeTextChangesAndOutsideSelectionEndMultiCursor() {
    selectThree()
    view.reloadText(with: "짧은 글")
    XCTAssertNil(view.multiCursorRanges)

    view.replaceAllText(with: "민준 가 민준 나 민준")
    selectThree()
    XCTAssertTrue(view.replaceAllUndoably(with: "다른 글", actionName: "복원"))
    XCTAssertNil(view.multiCursorRanges)

    view.replaceAllText(with: "민준 가 민준 나 민준")
    selectThree()
    view.setSelectedRange(NSRange(location: 4, length: 0))
    XCTAssertNil(view.multiCursorRanges, "클릭처럼 바깥에서 옮긴 선택")

    selectThree()
    view.replaceAllText(with: "새 회차")
    XCTAssertNil(view.multiCursorRanges)
    XCTAssertFalse(view.hasMarkedText())
  }

  /// 입력기가 맨 앞 커서 밖을 가리키면(재변환 등) 여러 커서를 끝내고 보통 입력으로(16장 I2).
  func testReplacementAwayFromFirstCursorFallsBackToOneCursor() {
    selectThree()
    key { view.insertText("가", replacementRange: none) }

    key { view.insertText("X", replacementRange: NSRange(location: 4, length: 1)) }

    XCTAssertNil(view.multiCursorRanges)
    XCTAssertEqual(view.string, "가 가 X 나 가")
  }

  /// 앱 몰래 본문이 짧아져 자리가 낡았으면 고치지 않고 끝낸다(16장 D1). 앱이 죽지 않는다.
  func testStaleRangesDoNotCrash() {
    selectThree()
    view.textStorage?.replaceCharacters(in: NSRange(location: 3, length: 9), with: "")

    key { view.insertText("가", replacementRange: none) }

    XCTAssertNil(view.multiCursorRanges)
  }

  /// 판을 열어 초점을 놓으면 모든 자리의 조합을 확정하고 여러 커서는 남는다(16장 D5, X1).
  func testYieldingFocusCommitsCompositionAtEveryCursor() {
    selectThree()
    key { view.setMarkedText("ㄷ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none) }

    _ = view.yieldFocusForPanel()

    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(view.string, "ㄷ 가 ㄷ 나 ㄷ")
    XCTAssertEqual(view.multiCursorRanges?.count, 3)
  }

  /// 모든 고치기가 바뀜 알림을 거쳐 자동 저장·글자 수가 안다(16장 D2).
  func testEditsAreAnnouncedForAutosave() {
    selectThree()
    var announced = 0
    let observer = NotificationCenter.default.addObserver(
      forName: NSText.didChangeNotification, object: view, queue: nil
    ) { _ in announced += 1 }
    defer { NotificationCenter.default.removeObserver(observer) }

    key { view.insertText("가", replacementRange: none) }

    XCTAssertEqual(announced, 1, "세 자리를 한 번에")
  }

  func testEscapeKeepsFirstCursor() {
    selectThree()

    view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

    XCTAssertNil(view.multiCursorRanges)
    XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 2))
  }
}
