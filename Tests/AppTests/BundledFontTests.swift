import AppKit
import XCTest

/// Pretendard가 앱에 들어 있고 시작할 때 등록되는지 확인한다.
final class BundledFontTests: XCTestCase {
  func testPretendardIsRegistered() {
    XCTAssertNotNil(NSFont(name: "Pretendard-Regular", size: 17))
  }

  func testPretendardLicenseIsBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "Pretendard-LICENSE", withExtension: "txt"))
  }
}
