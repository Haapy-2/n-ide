import Foundation

/// 원자적 쓰기: 같은 폴더의 임시 파일에 끝까지 쓰고 디스크에 확실히 내린 뒤, 한 번의 이름 바꾸기로 교체한다.
/// 이름 바꾸기는 운영체제가 한 번에 처리하므로, 도중에 앱이 죽어도 원래 파일이나 새 파일 중 하나만 남고
/// 반쯤 쓰인 파일은 생기지 않는다.
enum AtomicFile {
  /// `replacing: false`로 쓸 때 같은 이름의 파일이 이미 있었다. 아무것도 바뀌지 않았다.
  struct AlreadyExists: Error {}

  /// - Parameter replacing: false면 이미 있는 파일을 절대 덮지 않는다(스냅샷). 있으면 `AlreadyExists`를 던진다.
  ///   "있는지 보고 쓰기"는 보는 순간과 쓰는 순간 사이에 다른 쓰기가 끼어들 수 있어서, 확인과 쓰기를 운영체제가 한 번에 한다.
  /// - Parameter fullSync: false면 저장 장치까지만 보내고(fsync) 장치 캐시는 비우지 않는다(3.2 → 0.16ms).
  ///   F_FULLFSYNC는 장치 캐시 전체를 비우므로, 바로 뒤에 F_FULLFSYNC로 쓰는 파일이 있을 때 그 쓰기가 이 파일도 함께 내려 준다.
  ///   그렇게 순서가 보장되는 곳(전체 바꾸기의 스냅샷 → 본문)에서만 끈다.
  static func write(_ data: Data, to destination: URL, replacing: Bool = true, fullSync: Bool = true) throws {
    let folder = destination.deletingLastPathComponent()
    // 이름을 점으로 시작해 Finder에 보이지 않게 한다. 같은 폴더여야 이름 바꾸기가 원자적이다.
    let temp = folder.appending(
      path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)

    // FileManager.createFile은 실패 까닭을 알려 주지 않아 open으로 만든다(errno로 권한·공간 부족을 가린다).
    let descriptor = open(temp.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard descriptor >= 0 else {
      let code = errno
      throw ProjectError.writeFailed(
        destination, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
    }
    do {
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? handle.close() }
      try handle.write(contentsOf: data)
      // 전원이 갑자기 꺼져도 내용이 디스크에 남도록 이름을 바꾸기 전에 내려 쓴다.
      // 애플 기기에서 fsync는 저장 장치의 캐시까지는 비우지 않아 F_FULLFSYNC를 쓴다(측정 0.2 → 2.9ms, 메인 스레드 밖).
      // 이것을 지원하지 않는 파일 시스템(일부 네트워크 드라이브)에서는 fsync로 대신한다.
      if !fullSync || fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 {
        try handle.synchronize()
      }
    } catch {
      try? FileManager.default.removeItem(at: temp)
      throw ProjectError.writeFailed(destination, reason: error.localizedDescription, problem: WriteProblem(error: error))
    }

    let tempPath = temp.path(percentEncoded: false)
    let destinationPath = destination.path(percentEncoded: false)
    if replacing {
      if rename(tempPath, destinationPath) != 0 {
        let code = errno
        try? FileManager.default.removeItem(at: temp)
        throw ProjectError.writeFailed(destination, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
      }
    } else {
      // link는 새 이름이 이미 있으면 실패하고, 성공하면 다 쓴 파일이 한 번에 그 이름으로 보인다. 그 뒤 임시 이름만 지운다.
      if link(tempPath, destinationPath) != 0 {
        let code = errno
        if code == EEXIST {
          try? FileManager.default.removeItem(at: temp)
          throw AlreadyExists()
        }
        // 하드 링크를 못 만드는 파일 시스템(exFAT·FAT 외장 디스크, 일부 네트워크 드라이브)에서는 다른 방법으로 넣는다.
        try placeWithoutLink(temp: tempPath, destination: destinationPath, url: destination)
        return
      }
      unlink(tempPath)
    }
  }

  /// `link` 대신: 빈 파일로 이름을 먼저 차지하고(O_EXCL, 이미 있으면 운영체제가 거절) 다 쓴 임시 파일을 그 위로 바꿔 넣는다.
  /// 차지한 이름은 이 쓰기만의 것이라 덮어도 남의 파일을 덮지 않는다. 바꿔 넣기 전에 앱이 죽으면 빈 파일이 남을 수 있어 `link`가 될 때는 쓰지 않는다.
  static func placeWithoutLink(temp: String, destination: String, url: URL) throws {
    let placeholder = open(destination, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard placeholder != -1 else {
      let code = errno
      unlink(temp)
      if code == EEXIST { throw AlreadyExists() }
      throw ProjectError.writeFailed(url, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
    }
    close(placeholder)
    if rename(temp, destination) != 0 {
      let code = errno
      unlink(temp)
      unlink(destination)
      throw ProjectError.writeFailed(url, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
    }
  }
}
