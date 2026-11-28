import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// Arrows and delete with multi-cursor (PLAN ch.16 E5). Targets are computed directly, so first compare against where the single-cursor editor goes with the same key
/// at every character position.
@MainActor
final class MultiCursorMovementTests: XCTestCase {
  private var view: ManuscriptTextView!
  private let none = NSRange(location: NSNotFound, length: 0)

  /// Hangul, punctuation, quotes, emoji, decomposed Hangul, blank lines, long wrapped paragraphs, trailing newline
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

  /// At a wrap point, the next line's start (how multi-cursor views that position). A program-placed caret defaults to the previous line's end.
  private func caret(at index: Int) {
    view.setSelectedRange(NSRange(location: index, length: 0), affinity: .downstream, stillSelecting: false)
  }

  /// Positions a caret can stand at (not inside one character)
  private var caretIndices: [Int] {
    let text = sample as NSString
    return (0...text.length).filter { $0 == text.length || text.rangeOfComposedCharacterSequence(at: $0).location == $0 }
  }

  private func cursors(_ ranges: [NSRange]) {
    view.multiCursor = MultiCursorSession(cursor: MultiCursor(ranges: ranges, wholeWord: false)!)
    view.selectPrimary()
  }

  // MARK: - Same as a single cursor?

  /// Per command, the number of mismatches and the first few
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

  // MARK: - Multi-cursor

  private func command(_ selector: Selector) {
    view.doCommand(by: selector)
  }

  /// Three "민준" selected with ⌘D
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

  /// Even after passing short lines, each spot returns to its original horizontal position.
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

  /// ⌥⌫ deletes the previous word at each spot, and one ⌘Z brings all spots back.
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

