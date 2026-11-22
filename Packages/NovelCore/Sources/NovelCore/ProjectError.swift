import Foundation

/// 작품 파일을 다루다 생기는 오류. 화면에 보여줄 설명은 앱 쪽에서 붙인다.
public enum ProjectError: Error, Equatable, Sendable {
  /// 같은 이름의 작품 폴더가 이미 있다. 덮어쓰지 않는다.
  case alreadyExists(URL)
  case missingProjectFile(URL)
  /// `project.json`을 읽을 수 없다(형식이 깨짐).
  case corruptProjectFile(URL)
  /// 앱이 아는 것보다 새 형식이다. 고치지 않고 열기를 거부한다.
  case newerSchemaVersion(found: Int, supported: Int)
  /// 회차나 노트 본문 파일이 없다.
  case missingTextFile(URL)
  case notUTF8(URL)
  case writeFailed(URL, reason: String, problem: WriteProblem = .other)
}

/// 저장이 실패한 까닭을 사용자가 할 수 있는 일로 나눈 것. 앱이 알맞은 안내와 버튼을 고른다.
public enum WriteProblem: Equatable, Sendable {
  /// 쓸 권한이 없다(폴더 권한).
  case noPermission
  /// 파일이나 폴더가 잠겨 있다(Finder "잠김").
  case locked
  /// 읽기 전용 디스크.
  case readOnlyVolume
  /// 디스크 공간이 모자라다.
  case diskFull
  /// 작품 폴더나 그 안 폴더가 없다(외장 디스크가 빠졌거나 옮김).
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

  /// Foundation 오류에서. POSIX 코드가 들어 있으면 그것을, 아니면 Cocoa 파일 오류 코드를 본다.
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
