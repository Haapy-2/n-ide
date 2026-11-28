import XCTest
@testable import NovelEditor

/// A short duration so the test doesn't wait the real toast time (default 2 s). Generous margins so it doesn't flake when the machine is busy.
@MainActor
final class ToastTests: XCTestCase {
  private let short = Duration.milliseconds(300)

  func testDisappearsAfterDuration() async throws {
    let center = ToastCenter(duration: short)
    center.show("저장했어요")
    XCTAssertEqual(center.current?.message, "저장했어요")
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNotNil(center.current, "정한 시간 전에는 남아 있다")
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertNil(center.current)
  }

  /// Setting "toast duration": 2 s if absent, out-of-range clamped to 0.5–5 s, snapped to 0.5 s steps.
  func testStoredDuration() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "ToastTests-\(UUID().uuidString)"))
    XCTAssertEqual(ToastCenter.storedDuration(defaults), .seconds(2))
    for (stored, expected) in [(0.1, 500), (9.0, 5_000), (1.2, 1_000), (3.5, 3_500), (Double.nan, 2_000)] {
      defaults.set(stored, forKey: AppSettingKey.toastDuration)
      XCTAssertEqual(ToastCenter.storedDuration(defaults), .milliseconds(expected), "\(stored)")
    }
  }

  func testNewToastReplacesOldAndRestartsTimer() async throws {
    let center = ToastCenter(duration: short)
    center.show("저장했어요")
    try await Task.sleep(for: .milliseconds(200))
    center.show("스냅샷을 찍었어요")
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(center.current?.message, "스냅샷을 찍었어요", "앞 토스트의 시간에 새 토스트가 닫히지 않는다")
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertNil(center.current)
  }

  func testWaitsWhileHovering() async throws {
    let center = ToastCenter(duration: short)
    center.show("저장했어요")
    center.setHovering(true)
    try await Task.sleep(for: .milliseconds(600))
    XCTAssertNotNil(center.current, "마우스가 올라가 있으면 사라지지 않는다")
    center.setHovering(false)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNotNil(center.current, "내려간 뒤 다시 센다")
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertNil(center.current)
  }

  func testActionRunsOnceAndDismisses() {
    let center = ToastCenter(duration: short)
    var count = 0
    center.show("스냅샷을 찍었어요", action: Toast.Action(title: "메모 달기") { count += 1 })
    center.performAction()
    XCTAssertEqual(count, 1)
    XCTAssertNil(center.current)
    center.performAction()
    XCTAssertEqual(count, 1, "닫힌 뒤에는 다시 실행되지 않는다")
  }
}
