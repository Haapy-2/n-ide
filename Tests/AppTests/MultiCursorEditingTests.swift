import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// Same-word multi-cursor (⌘D, PLAN ch.16). IME calls are replayed in exactly the order seen in the ch.16 #5 experiment.
@MainActor
final class MultiCursorEditingTests: XCTestCase {
  private var view: ManuscriptTextView!
  private let none = NSRange(location: NSNotFound, length: 0)

  private var undo: UndoManager { view.episodeUndoManager }

  override func setUp() async throws {
    view = ManuscriptTextView.make()
    view.replaceAllText(with: "민준 가 민준 나 민준")
    // Tests have no events, so undo groups don't close by themselves. Each key is closed as one group directly.
    undo.groupsByEvent = false
  }

  private func key(_ body: () -> Void) {
    undo.beginUndoGrouping()
    body()
    undo.endUndoGrouping()
  }

  /// `count` characters before the leading caret (the range the IME gives when replacing "the previous character with this")
  private func beforeCaret(_ count: Int) -> NSRange {
    NSRange(location: view.selectedRange().location - count, length: count)
  }

  private func selectThree() {
    view.setSelectedRange(NSRange(location: 0, length: 2))
    view.selectNextOccurrence(nil)
    view.selectNextOccurrence(nil)
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [0, 5, 10])
  }

  /// 2-set composition without displayed text (ch.16 #5 ⓐ): ㄷ → 도 → 동 → 도 + 유 → 윤.
  /// Keys that edit the same character only grow the record and don't open a group (the real app also opens a group only when a record is made).
  /// If such a key secretly left a record, there'd be no open group and it would surface as an exception.
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

  // MARK: - Hangul input

  func testReplacementModeHangulGoesToEveryCursor() {
    selectThree()

    typeDoyunReplacing()

    XCTAssertEqual(view.string, "도윤 가 도윤 나 도윤")
    XCTAssertEqual(view.multiCursorRanges, [2, 7, 12].map { NSRange(location: $0, length: 0) })
    XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0))
    XCTAssertFalse(view.hasMarkedText())
  }

  /// Displayed-text mode (ch.16 #5 ⓑ). During composition every spot is composing, and the IME is told the leading spot's composing range.
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

  /// Carets meeting while deleting become one. With only one left, back to the plain editor.
  func testCursorsThatMeetBecomeOne() {
    view.replaceAllText(with: "가가")
    view.setSelectedRange(NSRange(location: 0, length: 1))
    view.selectNextOccurrence(nil)

    key { view.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }

    XCTAssertEqual(view.string, "")
    XCTAssertNil(view.multiCursorRanges)
  }

  /// With line numbers on, Return with multi-cursor keeps the line count right (counted once after all edits, not per spot).
  func testLineCountFollowsMultiCursorNewlines() {
    view.showsLineNumbers = true
    XCTAssertEqual(view.currentLineCount, 1)
    selectThree()

    key { view.doCommand(by: #selector(NSResponder.insertNewline(_:))) }

    XCTAssertEqual(view.currentLineCount, 4)
  }

  /// Even when deleting touching selections meets at one point, ⌘Z restores all deleted text (E4), and records below apply to their own characters.
  func testUndoAfterCursorsMeetRestoresEveryDeletedCharacter() {
    view.replaceAllText(with: "가가 나다")
    view.setSelectedRange(NSRange(location: 3, length: 0))
    key { view.insertText("사", replacementRange: none) }
    view.setSelectedRange(NSRange(location: 0, length: 1))
    view.selectNextOccurrence(nil)
    XCTAssertEqual(view.multiCursorRanges, [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1)])

    key { view.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }
    XCTAssertEqual(view.string, " 사나다")

    view.undo(nil)
    XCTAssertEqual(view.string, "가가 사나다")
    XCTAssertEqual(view.multiCursorRanges, [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1)])
    view.undo(nil)
    XCTAssertEqual(view.string, "가가 나다")
  }

  /// Even when deleting during composition (the IME sends empty text) makes touching spots meet, ⌘Z brings back the selected text.
  func testUndoAfterCompositionDeletedAtMeetingCursors() {
    view.replaceAllText(with: "가가 나")
    view.setSelectedRange(NSRange(location: 0, length: 1))
    view.selectNextOccurrence(nil)

    key { view.setMarkedText("ㄷ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none) }
    view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: none)
    XCTAssertEqual(view.string, " 나")

    view.undo(nil)
    XCTAssertEqual(view.string, "가가 나")
  }

  // MARK: - Undo

  /// One composition (one character) is one ⌘Z unit across all spots (ch.16 U1). Undo returns to the carets of that time (U2).
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

  // MARK: - Collisions with other paths

  /// Paths replacing the whole body (episode switch, external change, snapshot restore) and program-moved selections end multi-cursor (ch.16 D3).
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

  /// If the IME points outside the leading caret (reconversion etc.), end multi-cursor and fall back to normal input (ch.16 I2).
  func testReplacementAwayFromFirstCursorFallsBackToOneCursor() {
    selectThree()
    key { view.insertText("가", replacementRange: none) }

    key { view.insertText("X", replacementRange: NSRange(location: 4, length: 1)) }

    XCTAssertNil(view.multiCursorRanges)
    XCTAssertEqual(view.string, "가 가 X 나 가")
  }

  /// If the body shrank behind the app's back and spots went stale, end without editing (ch.16 D1). The app doesn't crash.
  func testStaleRangesDoNotCrash() {
    selectThree()
    view.textStorage?.replaceCharacters(in: NSRange(location: 3, length: 9), with: "")

    key { view.insertText("가", replacementRange: none) }

    XCTAssertNil(view.multiCursorRanges)
  }

  /// Opening the panel and releasing focus commits composition at every spot while multi-cursor remains (ch.16 D5, X1).
  func testYieldingFocusCommitsCompositionAtEveryCursor() {
    selectThree()
    key { view.setMarkedText("ㄷ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none) }

    _ = view.yieldFocusForPanel()

    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(view.string, "ㄷ 가 ㄷ 나 ㄷ")
    XCTAssertEqual(view.multiCursorRanges?.count, 3)
  }

  /// Every edit goes through change notifications so autosave and counting know (ch.16 D2).
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

  // MARK: - Blinking

  // The system calls `drawInsertionPoint(turnedOn: true)` only when turning the caret on; to turn it off it just redraws that rect.
  // The two tests below replay those two moments.

  /// Type one character at each of three spots so all become carets (length 0). Drawing needs a window-sized frame and layout.
  private func threeCarets() {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
    scrollView.documentView = view
    view.setFrameSize(NSSize(width: 800, height: 300))
    view.style = EditorStyle()
    selectThree()
    key { view.insertText("가", replacementRange: none) }
    XCTAssertEqual(view.multiCursorRanges?.map(\.length), [0, 0, 0])
    view.layoutManager?.ensureLayout(for: view.textContainer!)
  }

  /// The leading caret rect the system provides (line height, 1 pt wide).
  private func systemCaretRect() -> NSRect {
    let layoutManager = view.layoutManager!
    let index = view.selectedRange().location
    let glyph = layoutManager.glyphIndexForCharacter(at: index - 1)
    var line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer!)
    line.origin.x = box.maxX
    line.size.width = 1
    return line.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
  }

  /// Color at point `point` in the drawn image (flipped 1× bitmap).
  private func pixel(at point: NSPoint, _ draw: (NSBitmapImageRep) -> Void) -> NSColor? {
    let size = view.bounds.size
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    draw(rep)
    return rep.colorAt(x: Int(point.x), y: Int(point.y))
  }

  /// Center of the second spot's caret.
  private func secondCaretCenter() -> NSPoint {
    let caret = view.extraCaretRect(at: view.multiCursorRanges![1].location)!
    return NSPoint(x: caret.midX, y: caret.midY)
  }

  /// When the caret turns on, other carets are drawn in the same draw (not deferred to the next refresh).
  func testExtraCaretsTurnOnInTheSameDrawAsFirstCaret() {
    threeCarets()

    let pixel = self.pixel(at: secondCaretCenter()) { rep in
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      let flip = NSAffineTransform()
      flip.translateX(by: 0, yBy: view.bounds.height)
      flip.scaleX(by: 1, yBy: -1)
      flip.concat()
      view.drawInsertionPoint(in: systemCaretRect(), color: .red, turnedOn: true)
      NSGraphicsContext.restoreGraphicsState()
    }

    XCTAssertGreaterThan(pixel?.alphaComponent ?? 0, 0.5, "맨 앞 커서와 함께 켜져야 한다")
  }

  /// Redrawing the leading caret rect after it's on (how the system turns it off) turns the other carets off too.
  func testExtraCaretsTurnOffWhenFirstCaretIsRedrawn() {
    threeCarets()
    let image = NSImage(size: view.bounds.size)
    image.lockFocusFlipped(true)
    view.drawInsertionPoint(in: systemCaretRect(), color: .red, turnedOn: true)
    image.unlockFocus()

    let center = secondCaretCenter()
    let pixel = self.pixel(at: center) { rep in view.cacheDisplay(in: view.bounds, to: rep) }

    view.dropMultiCursor()
    let background = self.pixel(at: center) { rep in view.cacheDisplay(in: view.bounds, to: rep) }
    XCTAssertEqual(pixel, background, "맨 앞 커서가 지워진 그림에는 다른 자리 커서도 없어야 한다")
  }

  // MARK: - Copy and paste

  /// A per-test pasteboard so the user's clipboard isn't touched
  private let board = NSPasteboard(name: NSPasteboard.Name("NovelEditorTests-\(UUID().uuidString)"))

  func testCopyJoinsSelectionsAndPasteSpreadsThemBack() {
    view.replaceAllText(with: "민준 가 도윤 나 서연")
    view.multiCursor = MultiCursorSession(cursor: MultiCursor(
      ranges: [NSRange(location: 0, length: 2), NSRange(location: 5, length: 2), NSRange(location: 10, length: 2)], wholeWord: false)!)

    view.multiCursorCopy(to: board)
    XCTAssertEqual(board.string(forType: .string), "민준\n도윤\n서연")

    board.clearContents()
    board.setString("하나\n둘\n셋\n", forType: .string)
    key { view.multiCursorPaste(from: board) }
    XCTAssertEqual(view.string, "하나 가 둘 나 셋", "끝 줄바꿈을 떼면 세 줄 = 커서 셋")
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [2, 6, 10])

    undo.undo()
    XCTAssertEqual(view.string, "민준 가 도윤 나 서연", "⌘Z 한 번")
  }

  func testPasteSameTextEverywhereWhenLineCountDiffers() {
    selectThree()
    board.clearContents()
    board.setString("가\n나", forType: .string)

    key { view.multiCursorPaste(from: board) }

    XCTAssertEqual(view.string, "가\n나 가 가\n나 나 가\n나")
  }

  func testCutRemovesEverySelectionAsOneUndo() {
    selectThree()

    key { view.multiCursorCut(to: board) }

    XCTAssertEqual(board.string(forType: .string), "민준\n민준\n민준")
    XCTAssertEqual(view.string, " 가  나 ")
    XCTAssertEqual(view.multiCursorRanges?.map(\.location), [0, 3, 6])
    undo.undo()
    XCTAssertEqual(view.string, "민준 가 민준 나 민준")
  }

  func testCopyWithOnlyCaretsLeavesClipboardAlone() {
    selectThree()
    key { view.insertText("가", replacementRange: none) }
    board.clearContents()
    board.setString("그대로", forType: .string)

    view.multiCursorCopy(to: board)
    key { view.multiCursorCut(to: board) }

    XCTAssertEqual(board.string(forType: .string), "그대로")
    XCTAssertEqual(view.string, "가 가 가 나 가")
  }

  // MARK: - Safety net (ch.16 #4)

  func testTurnedOffCommandDDoesNothing() {
    view.multiCursorEnabled = false
    view.setSelectedRange(NSRange(location: 0, length: 2))
    view.selectNextOccurrence(nil)
    XCTAssertNil(view.multiCursorRanges)
    XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 2))

    view.setSelectedRange(NSRange(location: 6, length: 0))
    view.selectNextOccurrence(nil)
    XCTAssertEqual(view.selectedRange(), NSRange(location: 6, length: 0), "커서 아래 단어도 고르지 않는다")
  }

  func testTurningOffDuringCompositionCommitsAndEnds() {
    selectThree()
    key { view.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none) }

    view.multiCursorEnabled = false

    XCTAssertNil(view.multiCursorRanges)
    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(view.string, "ㄱ 가 ㄱ 나 ㄱ", "조합 중인 글자는 모든 자리에 그대로 남는다")
    XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 0), "맨 앞 자리 하나로")
  }

  func testEnterCallbackOnlyWhenSecondCursorAppearsBeforeAnyChange() {
    var seen: [String] = []
    let view = view!
    view.onEnterMultiCursor = { [unowned view] in seen.append(view.string) }

    selectThree()
    XCTAssertEqual(seen, ["민준 가 민준 나 민준"], "세 번째 자리를 더할 때는 다시 부르지 않는다")

    key { view.insertText("서윤", replacementRange: none) }
    view.endMultiCursor()
    view.setSelectedRange(NSRange(location: 0, length: 2))
    view.selectNextOccurrence(nil)
    XCTAssertEqual(seen, ["민준 가 민준 나 민준", "서윤 가 서윤 나 서윤"])
  }

  /// Goes through the SwiftUI bridge like the real app: the limit notice comes out of the bridge, and turning the setting off ends multi-cursor.
  func testBridgeCarriesLimitNoticeAndSwitch() async throws {
    var notices: [String] = []
    var editor: ManuscriptTextView?
    let content = ManuscriptEditor.Content(
      token: UUID(), episodeID: EpisodeID.make(), text: String(repeating: "가 ", count: MultiCursor.limit + 1))
    func bridge(enabled: Bool) -> ManuscriptEditor {
      ManuscriptEditor(
        content: content, multiCursorEnabled: enabled, onReady: { editor = $0 }, onNotice: { notices.append($0) })
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let host = NSHostingView(rootView: bridge(enabled: true))
    window.contentView = host
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(100))
    let textView = try XCTUnwrap(editor)

    textView.setSelectedRange(NSRange(location: 0, length: 1))
    for _ in 1..<MultiCursor.limit { textView.selectNextOccurrence(nil) }
    XCTAssertEqual(textView.multiCursorRanges?.count, 1_000)
    XCTAssertTrue(notices.isEmpty)
    textView.selectNextOccurrence(nil)
    XCTAssertEqual(notices, ["커서는 1,000개까지 만들 수 있어요"])
    XCTAssertEqual(textView.multiCursorRanges?.count, 1_000)

    host.rootView = bridge(enabled: false)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNil(textView.multiCursorRanges, "설정을 끄면 여러 커서를 끝낸다")
    textView.selectNextOccurrence(nil)
    XCTAssertNil(textView.multiCursorRanges)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 1))
  }
}

