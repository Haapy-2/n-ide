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

  // MARK: - 깜빡임

  // 시스템은 커서를 켤 때만 `drawInsertionPoint(turnedOn: true)`를 부르고, 끌 때는 그 칸을 다시 그리기만 한다.
  // 아래 두 테스트는 그 두 순간을 재생한다.

  /// 세 자리에 한 글자씩 쳐서 모두 커서(길이 0)로 만든다. 그리려면 창 크기만 한 틀과 배치가 있어야 한다.
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

  /// 시스템이 주는 맨 앞 커서 칸(줄 높이, 폭 1pt).
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

  /// 그린 그림에서 `point` 점의 색(뒤집힌 1배 비트맵).
  private func pixel(at point: NSPoint, _ draw: (NSBitmapImageRep) -> Void) -> NSColor? {
    let size = view.bounds.size
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    draw(rep)
    return rep.colorAt(x: Int(point.x), y: Int(point.y))
  }

  /// 둘째 자리 커서 한가운데.
  private func secondCaretCenter() -> NSPoint {
    let caret = view.extraCaretRect(at: view.multiCursorRanges![1].location)!
    return NSPoint(x: caret.midX, y: caret.midY)
  }

  /// 커서를 켜는 순간, 다른 자리 커서도 같은 그리기에서 그려진다(다음 화면 갱신으로 미루지 않는다).
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

  /// 켜진 뒤 맨 앞 커서 칸을 다시 그리면(시스템이 끄는 방법) 다른 자리 커서도 꺼진다.
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

  // MARK: - 복사와 붙여 넣기

  /// 사용자 클립보드를 건드리지 않게 테스트마다 따로 쓰는 붙여 넣기 판
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
}

