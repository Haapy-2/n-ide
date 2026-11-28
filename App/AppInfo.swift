import Foundation
import NovelCore

/// App name. The real value is set only in the Xcode build setting PRODUCT_NAME; code just reads it from the bundle.
enum AppInfo {
  static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NovelEditor"

  /// Emergency backup folder for manuscripts that couldn't be saved. Outside the project (this Mac's Application Support) so whatever broke the project folder doesn't block the backup.
  static var emergencyBackup: EmergencyBackup? {
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    return EmergencyBackup(folder: support.appending(path: "\(name)/Backups", directoryHint: .isDirectory))
  }
}
