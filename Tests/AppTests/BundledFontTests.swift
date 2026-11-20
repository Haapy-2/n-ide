import AppKit
import XCTest

final class BundledFontTests: XCTestCase {
  func testPretendardIsRegistered() {
    XCTAssertNotNil(NSFont(name: "Pretendard-Regular", size: 17))
  }

  func testPretendardLicenseIsBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "Pretendard-LICENSE", withExtension: "txt"))
  }
}
