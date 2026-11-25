import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// 여러 커서의 화살표·지우기(PLAN 16장 E5). 목표 자리는 직접 계산하므로, 커서 하나일 때 편집기가 같은 키로 가는 자리와
/// 모든 글자 자리에서 같은지 먼저 비교한다.
@MainActor
final class MultiCursorMovementTests: XCTestCase {
  private var view: ManuscriptTextView!
  private let none = NSRange(location: NSNotFound, length: 0)

  /// 한글·문장 부호·따옴표·이모지·자모를 따로 적은 한글·빈 줄·화면에서 접히는 긴 문단·끝 줄바꿈
  private let sample = "민준이는 \"어디 가?\" 하고 물었다.\n\n둘째 줄, 👍🏽 짧다\n"
    + "\u{1100}\u{1161}\u{11A8}\u{1102}\u{1161} 셋째 "
    + String(repeating: "아주 길어서 화면 폭을 넘어가면 접히는 문단이다 ", count: 6) + "끝.\n"

  override func setUp() async throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
    view = ManuscriptTextView.make()
    scrollView.documentView = view
    view.setFrameSize(NSSize(width: 700, height: 600))
    view.style = EditorStyle()
    view.replaceAllText(with: sample)
    view.layoutManager?.ensureLayout(for: view.textContainer!)
  }

  private var length: Int { (view.string as NSString).length }

  /// 줄이 접히는 자리에서는 다음 줄 처음으로(여러 커서가 그 자리를 보는 방법). 프로그램이 놓은 커서의 기본은 앞 줄 끝이다.
  private func caret(at index: Int) {
    view.setSelectedRange(NSRange(location: index, length: 0), affinity: .downstream, stillSelecting: false)
  }

  /// 커서가 설 수 있는 자리(한 글자 가운데가 아닌 곳)
  private var caretIndices: [Int] {
    let text = sample as NSString
    return (0...text.length).filter { $0 == text.length || text.rangeOfComposedCharacterSequence(at: $0).location == $0 }
  }

  private func cursors(_ ranges: [NSRange]) {
    view.multiCursor = MultiCursorSession(cursor: MultiCursor(ranges: ranges, wholeWord: false)!)
    view.selectPrimary()
  }

  // MARK: - 커서 하나와 같은가

  /// 명령마다 다른 곳 수와 앞 몇 곳
  private func report(_ mismatches: [String]) -> String {
    let counts = Dictionary(grouping: mismatches) { $0.split(separator: " ")[0] }.map { "\($0.key) \($0.value.count)" }.sorted()
    return "\(mismatches.count)곳 다름 [\(counts.joined(separator: ", "))]\n" + mismatches.prefix(12).joined(separator: "\n")
  }

  func testMotionsMatchSingleCursorEditorAtEveryIndex() {
    XCTAssertGreaterThan(view.layoutManager!.numberOfGlyphs, 0)
    var mismatches: [String] = []
    let moves = ManuscriptTextView.multiCursorMoves.filter { !$0.value.1 }
    for (selector, (motion, _)) in moves.sorted(by: { NSStringFromSelector($0.key) < NSStringFromSelector($1.key) }) {
      for index in caretIndices {
        caret(at: index)
        view.doCommand(by: selector)
        let expected = view.selectedRange()
        let actual = view.cursorHead(motion, from: index, goalX: nil).head
        if expected.length != 0 || expected.location != actual {
          mismatches.append("\(NSStringFromSelector(selector)) \(index): 편집기 \(expected.location) 계산 \(actual)")
        }
      }
    }
    XCTAssertTrue(mismatches.isEmpty, report(mismatches))
  }

  func testDeletionsMatchSingleCursorEditorAtEveryIndex() {
    var mismatches: [String] = []
    for (selector, motion) in ManuscriptTextView.multiCursorDeletions.sorted(by: { NSStringFromSelector($0.key) < NSStringFromSelector($1.key) }) {
      for index in caretIndices {
        view.replaceAllText(with: sample)
        let stop = view.deletionStop(motion, from: index)
        caret(at: index)
        view.doCommand(by: selector)
        let expected = view.string
        let gone = NSRange(location: min(index, stop), length: abs(stop - index))
        let actual = (sample as NSString).replacingCharacters(in: gone, with: "")
        if expected != actual {
          let prefix = zip(sample.utf16, expected.utf16).prefix { $0 == $1 }.count
          let removed = (sample as NSString).length - (expected as NSString).length
          mismatches.append("\(NSStringFromSelector(selector)) \(index): 편집기 {\(prefix), \(removed)} 계산 \(gone)")
        }
      }
    }
    XCTAssertTrue(mismatches.isEmpty, report(mismatches))
  }

  // MARK: - 여러 커서

  private func command(_ selector: Selector) {
    view.doCommand(by: selector)
  }

  /// "민준" 세 곳을 ⌘D로 고른 상태
  private func selectThree(in text: String = "민준 가 민준 나 민준") {
    view.replaceAllText(with: text)
    view.setSelectedRange((text as NSString).range(of: "민준"))
    view.selectNextOccurrence(nil)
    view.selectNextOccurrence(nil)
    XCTAssertEqual(view.multiCursorRanges?.count, 3)
  }

  func testArrowsCollapseSelectionsThenMoveEveryCursor() {
    selectThree()

    command(#selector(NSResponder.moveLeft(_:)))
    XCTAssertEqual(view.multiCursorRanges, [0, 5, 10].map { NSRange(location: $0, length: 0) }, "선택 앞으로 모인다")
    command(#selector(NSResponder.moveRight(_:)))
    command(#selector(NSResponder.moveRight(_:)))
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [2, 7, 12])
    XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0), "편집기 선택은 맨 앞 자리")
  }

  func testShiftExtendsAndShrinksAtEveryCursorThenTypingReplaces() {
    view.replaceAllText(with: "가나 가나 가나")
    cursors([0, 3, 6].map { NSRange(location: $0, length: 0) })

    command(#selector(NSResponder.moveRightAndModifySelection(_:)))
    command(#selector(NSResponder.moveRightAndModifySelection(_:)))
    command(#selector(NSResponder.moveLeftAndModifySelection(_:)))
    XCTAssertEqual(view.multiCursorRanges, [0, 3, 6].map { NSRange(location: $0, length: 1) }, "붙박인 끝은 그대로라 줄어든다")

    view.insertText("다", replacementRange: none)
    XCTAssertEqual(view.string, "다나 다나 다나")
  }

  /// 짧은 줄을 지나도 자리마다 처음 가로 위치로 돌아온다.
  func testUpDownKeepEachCursorsColumn() {
    view.replaceAllText(with: "가나다라\n가\n가나다라\n가나다라\n가\n가나다라")
    cursors([NSRange(location: 3, length: 0), NSRange(location: 15, length: 0)])

    command(#selector(NSResponder.moveDown(_:)))
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [6, 18], "짧은 줄 끝")
    command(#selector(NSResponder.moveDown(_:)))
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [10, 22], "처음 가로 위치로")
    command(#selector(NSResponder.moveLeft(_:)))
    command(#selector(NSResponder.moveUp(_:)))
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [6, 18], "다른 명령 뒤에는 그때 자리에서 다시")
  }

  func testCursorsThatMeetBecomeOneCursor() {
    selectThree()

    command(#selector(NSResponder.moveToBeginningOfDocument(_:)))

    XCTAssertNil(view.multiCursorRanges)
    XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
  }

  func testScrollingKeepsCursors() {
    selectThree()

    command(#selector(NSResponder.scrollPageDown(_:)))

    XCTAssertEqual(view.multiCursorRanges?.count, 3)
  }

  /// ⌥⌫는 자리마다 앞 단어를 지우고, ⌘Z 한 번에 모든 자리가 돌아온다.
  func testWordDeletionAtEveryCursorUndoesAsOne() {
    view.replaceAllText(with: "민준이 가 민준이 나")
    cursors([NSRange(location: 3, length: 0), NSRange(location: 9, length: 0)])

    command(#selector(NSResponder.deleteWordBackward(_:)))
    XCTAssertEqual(view.string, " 가  나")
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [0, 3])

    view.episodeUndoManager.undo()
    XCTAssertEqual(view.string, "민준이 가 민준이 나")
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [3, 9])
  }

  func testForwardAndLineDeletionAtEveryCursor() {
    view.replaceAllText(with: "가나다\n가나다")
    cursors([NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)])

    command(#selector(NSResponder.deleteForward(_:)))
    XCTAssertEqual(view.string, "가다\n가다")
    command(#selector(NSResponder.deleteToBeginningOfLine(_:)))
    XCTAssertEqual(view.string, "다\n다")
  }
}

