import Foundation

/// 앱 이름. 실제 값은 Xcode 빌드 설정 PRODUCT_NAME 한 곳에서 정하고, 코드는 번들에서 읽기만 한다.
enum AppInfo {
  static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NovelEditor"
}
