import Foundation

/// Errors from handling project files. User-facing descriptions are added on the app side.
public enum ProjectError: Error, Equatable, Sendable {
  /// A project folder with the same name already exists. Never overwritten.
  case alreadyExists(URL)
  case missingProjectFile(URL)
  /// `project.json` can't be read (corrupt format).
  case corruptProjectFile(URL)
  /// Newer format than the app knows. Refuses to open without modifying it.
  case newerSchemaVersion(found: Int, supported: Int)
  /// An episode or note body file is missing.
  case missingTextFile(URL)
  case notUTF8(URL)
  case writeFailed(URL, reason: String, problem: WriteProblem = .other)
}

/// Why saving failed, grouped by what the user can do. The app picks fitting guidance and buttons.
public enum WriteProblem: Equatable, Sendable {
  /// No write permission (folder permissions).
  case noPermission
  /// The file or folder is locked (Finder "Locked").
  case locked
  /// Read-only disk.
  case readOnlyVolume
  /// Not enough disk space.
  case diskFull
  /// The project folder or a folder inside it is missing (external disk ejected or moved).
  case missingFolder
  case other

  public init(errno code: Int32) {
    switch code {
    case EACCES: self = .noPermission
    case EPERM: self = .locked
    case EROFS: self = .readOnlyVolume
    case ENOSPC, EDQUOT: self = .diskFull
    case ENOENT, ENOTDIR: self = .missingFolder
    default: self = .other
    }
  }

  /// From a Foundation error. Uses the POSIX code if present, otherwise the Cocoa file error code.
  public init(error: Error) {
    let error = error as NSError
    if error.domain == NSPOSIXErrorDomain {
      self.init(errno: Int32(error.code))
      return
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
      self.init(errno: Int32(underlying.code))
      return
    }
    switch error.code {
    case NSFileWriteNoPermissionError: self = .noPermission
    case NSFileWriteOutOfSpaceError: self = .diskFull
    case NSFileWriteVolumeReadOnlyError: self = .readOnlyVolume
    case NSFileNoSuchFileError: self = .missingFolder
    default: self = .other
    }
  }
}
