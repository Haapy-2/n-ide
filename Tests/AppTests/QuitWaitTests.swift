import XCTest
@testable import NovelEditor

/// 종료 때 저장이 늦으면 알림을 띄울지 정하는 기다림. 늦어도 저장 작업은 취소하지 않는다.
@MainActor
final class QuitWaitTests: XCTestCase {
  func testQuickWorkFinishesWithinLimit() async {
    let work = Task<Void, Never> { @MainActor in }
    let finished = await AppDelegate.finishes(work, within: .seconds(2))
    XCTAssertTrue(finished)
  }

  func testSlowWorkIsReportedButKeepsRunning() async {
    var done = false
    let work = Task<Void, Never> { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      done = true
    }
    let started = ContinuousClock.now
    let finished = await AppDelegate.finishes(work, within: .milliseconds(50))
    XCTAssertFalse(finished)
    XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(250), "한도에서 바로 돌아온다")
    await work.value
    XCTAssertTrue(done, "늦어도 저장은 끝까지 한다")
  }
}
