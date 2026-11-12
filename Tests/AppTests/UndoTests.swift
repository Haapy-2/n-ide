import AppKit
import XCTest
@testable import NovelEditor

/// 편집기 ⌘Z·⇧⌘Z(회차 기록으로 보내기)와 사이드바 되돌리기 확인 창의 "다시 묻지 않기" 기간.
@MainActor
final class UndoTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    defaults = UserDefaults(suiteName: "UndoTests-\(UUID().uuidString)")
  }

  /// 편집 메뉴의 실행 취소(`undo:`)가 편집기에서 처리되어 회차 기록으로 되돌리고, 다시 실행으로 되살린다.
  func testEditorHandlesUndoAndRedoMenuActions() {
    let textView = ManuscriptTextView.make()
    textView.replaceAllText(with: "그는")
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.insertText(" 웃었다", replacementRange: NSRange(location: NSNotFound, length: 0))
    // 입력 묶음은 한 차례가 끝나야 닫힌다.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    XCTAssertTrue(textView.responds(to: Selector(("undo:"))))
    textView.undo(nil)
    XCTAssertEqual(textView.string, "그는")
    textView.redo(nil)
    XCTAssertEqual(textView.string, "그는 웃었다")
  }

  /// 조합 중에 ⌘Z를 누르면 조합을 먼저 확정하고 되돌려, 조합 글자가 남거나 깨지지 않는다.
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
    let item = NSMenuItem(title: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
    XCTAssertFalse(textView.validateUserInterfaceItem(item))
  }

  // MARK: - 확인 창 쉬기

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
