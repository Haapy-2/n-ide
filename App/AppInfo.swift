import Foundation
import NovelCore

/// 앱 이름. 실제 값은 Xcode 빌드 설정 PRODUCT_NAME 한 곳에서 정하고, 코드는 번들에서 읽기만 한다.
enum AppInfo {
  static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NovelEditor"

  /// 저장하지 못한 원고의 비상 백업 폴더. 작품 폴더를 못 쓰게 만든 원인이 백업까지 막지 않도록 작품 밖(이 맥의 앱 지원 폴더).
  static var emergencyBackup: EmergencyBackup? {
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    return EmergencyBackup(folder: support.appending(path: "\(name)/Backups", directoryHint: .isDirectory))
  }
}
