import XCTest
@testable import NovelEditor

/// 실제 알림 시간(기본 2초)을 기다리지 않으려고 짧은 시간으로 만든다. 기기가 바빠도 흔들리지 않게 여유를 넉넉히 둔다.
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

  /// 설정 "알림 유지 시간": 없으면 2초, 범위 밖은 0.5~5초로, 단위는 0.5초로 맞춘다.
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
