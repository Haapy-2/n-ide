import AppKit
import XCTest
@testable import NovelEditor

@MainActor
final class UndoTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    defaults = UserDefaults(suiteName: "UndoTests-\(UUID().uuidString)")
  }

  /// Edit menu undo (`undo:`) is handled by the editor and reverts via the episode history; redo brings it back.
  func testEditorHandlesUndoAndRedoMenuActions() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "그는")
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.insertText(" 웃었다", replacementRange: NSRange(location: NSNotFound, length: 0))
    // An input group closes only after a turn ends.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    XCTAssertTrue(textView.responds(to: #selector(ManuscriptTextView.undo(_:))))
    textView.undo(nil)
    XCTAssertEqual(textView.string, "그는")
    textView.redo(nil)
    XCTAssertEqual(textView.string, "그는 웃었다")
  }

  /// Undo one character at a time. For Hangul, one finished character is one unit.
  func testUndoRemovesOneCharacterAtATime() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "")
    let none = NSRange(location: NSNotFound, length: 0)
    // In the real app each keystroke's event turn ends and closes the undo group. Tests create that boundary directly.
    let undo = textView.episodeUndoManager
    undo.groupsByEvent = false
    for letter in ["가", "나", "다"] {
      undo.beginUndoGrouping()
      // Insert in composition (jamo) → commit order like an IME.
      textView.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
      textView.insertText(letter, replacementRange: none)
      undo.endUndoGrouping()
    }
    XCTAssertEqual(textView.string, "가나다")

    textView.undo(nil)
    XCTAssertEqual(textView.string, "가나")
    textView.undo(nil)
    XCTAssertEqual(textView.string, "가")
    textView.redo(nil)
    XCTAssertEqual(textView.string, "가나")
  }

  /// The macOS 27 2-set IME continues composing without displayed text via "replace the one character before the caret with this" (replacementRange).
  /// Feed the call order recorded in the real app (ㄱ → 가 → 각 → 가 + 가) per key, and check undo never shows mid-composition characters ("각", "ㄱ").
  /// Opening/closing a group per key by hand would turn keys that leave nothing into empty groups eating a ⌘Z, so only changes to visible text are counted.
  func testUndoSkipsJamoStepsOfReplacementInput() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "")
    let undo = textView.episodeUndoManager
    undo.groupsByEvent = false
    let none = NSRange(location: NSNotFound, length: 0)
    let previous = NSRange(location: 0, length: 1)
    func key(_ calls: [(String, NSRange)]) {
      undo.beginUndoGrouping()
      for (text, range) in calls { textView.insertText(text, replacementRange: range) }
      undo.endUndoGrouping()
    }
    key([("ㄱ", none)])
    key([("가", previous)])
    key([("각", previous)])
    key([("가", previous), ("가", none)])
    XCTAssertEqual(textView.string, "가가")

    var seen = [textView.string]
    while undo.canUndo {
      textView.undo(nil)
      if seen.last != textView.string { seen.append(textView.string) }
    }
    XCTAssertEqual(seen, ["가가", "가", ""])

    var redone = [textView.string]
    while undo.canRedo {
      textView.redo(nil)
      if redone.last != textView.string { redone.append(textView.string) }
    }
    XCTAssertEqual(redone, ["", "가", "가가"])
  }

  /// Characters typed via real keystrokes (keyDown) also undo one at a time. NSTextView coalesces consecutive typed characters into one group,
  /// so this test verifies the group breaking. Digits go in directly without composition even with the Hangul IME.
  func testTypedKeysUndoOneAtATime() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let textView = ManuscriptTextView.make()
    textView.frame = window.contentLayoutRect
    window.contentView = textView
    window.makeFirstResponder(textView)
    textView.replaceAllText(with: "")
    let undo = textView.episodeUndoManager
    undo.groupsByEvent = false
    for key in ["1", "2", "3"] {
      let event = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 18))
      undo.beginUndoGrouping()
      textView.keyDown(with: event)
      undo.endUndoGrouping()
    }
    XCTAssertEqual(textView.string, "123")

    textView.undo(nil)
    XCTAssertEqual(textView.string, "12")
  }

  func testUndoDuringCompositionFinishesCompositionFirst() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "가")
    textView.setSelectedRange(NSRange(location: 1, length: 0))
    textView.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

    textView.undo(nil)

    XCTAssertFalse(textView.hasMarkedText())
    XCTAssertEqual(textView.string, "가")
  }

  func testUndoMenuIsDisabledWithNothingToUndo() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "가")
    let item = NSMenuItem(title: "실행 취소", action: #selector(ManuscriptTextView.undo(_:)), keyEquivalent: "z")
    XCTAssertFalse(textView.validateUserInterfaceItem(item))
  }

  // MARK: - Confirmation rest

  func testPauseLastsChosenPeriod() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    defaults.set(UndoConfirmPause.threeDays.rawValue, forKey: AppSettingKey.undoConfirmPause)
    XCTAssertFalse(UndoConfirmation.isPaused(now: now, defaults: defaults))

    UndoConfirmation.pause(now: now, defaults: defaults)

    XCTAssertTrue(UndoConfirmation.isPaused(now: now.addingTimeInterval(86_400 * 2), defaults: defaults))
    XCTAssertFalse(UndoConfirmation.isPaused(now: now.addingTimeInterval(86_400 * 3 + 3_600), defaults: defaults))
  }

  func testDefaultPauseIsAWeekAndForeverNeverEnds() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    UndoConfirmation.pause(now: now, defaults: defaults)
    XCTAssertTrue(UndoConfirmation.isPaused(now: now.addingTimeInterval(86_400 * 6), defaults: defaults))
    XCTAssertFalse(UndoConfirmation.isPaused(now: now.addingTimeInterval(86_400 * 8), defaults: defaults))

    defaults.set(UndoConfirmPause.forever.rawValue, forKey: AppSettingKey.undoConfirmPause)
    UndoConfirmation.pause(now: now, defaults: defaults)
    XCTAssertTrue(UndoConfirmation.isPaused(now: now.addingTimeInterval(86_400 * 3_650), defaults: defaults))
  }

  func testResumeAsksAgain() {
    UndoConfirmation.pause(defaults: defaults)
    UndoConfirmation.resume(defaults: defaults)
    XCTAssertFalse(UndoConfirmation.isPaused(defaults: defaults))
  }

  func testDialogTitleUsesRightParticle() {
    XCTAssertEqual(WorkspaceView.PendingUndo(isRedo: false, actionName: "이름 변경").title, "\"이름 변경\"을 되돌릴까요?")
    XCTAssertEqual(WorkspaceView.PendingUndo(isRedo: false, actionName: "새 회차").title, "\"새 회차\"를 되돌릴까요?")
    XCTAssertEqual(WorkspaceView.PendingUndo(isRedo: true, actionName: "목표 글자 수").title, "\"목표 글자 수\"를 다시 실행할까요?")
  }
}
