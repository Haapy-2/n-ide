import Foundation

/// 원자적 쓰기: 같은 폴더의 임시 파일에 끝까지 쓰고 디스크에 확실히 내린 뒤, 한 번의 이름 바꾸기로 교체한다.
/// 이름 바꾸기는 운영체제가 한 번에 처리하므로, 도중에 앱이 죽어도 원래 파일이나 새 파일 중 하나만 남고
/// 반쯤 쓰인 파일은 생기지 않는다.
enum AtomicFile {
  /// `replacing: false`로 쓸 때 같은 이름의 파일이 이미 있었다. 아무것도 바뀌지 않았다.
  struct AlreadyExists: Error {}

  /// - Parameter replacing: false면 이미 있는 파일을 절대 덮지 않는다(스냅샷). 있으면 `AlreadyExists`를 던진다.
  ///   "있는지 보고 쓰기"는 보는 순간과 쓰는 순간 사이에 다른 쓰기가 끼어들 수 있어서, 확인과 쓰기를 운영체제가 한 번에 한다.
  static func write(_ data: Data, to destination: URL, replacing: Bool = true) throws {
    let folder = destination.deletingLastPathComponent()
    // 이름을 점으로 시작해 Finder에 보이지 않게 한다. 같은 폴더여야 이름 바꾸기가 원자적이다.
    let temp = folder.appending(
      path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)

    guard FileManager.default.createFile(atPath: temp.path(percentEncoded: false), contents: nil) else {
      throw ProjectError.writeFailed(destination, reason: "임시 파일을 만들 수 없음")
    }
    do {
      let handle = try FileHandle(forWritingTo: temp)
      defer { try? handle.close() }
      try handle.write(contentsOf: data)
      // 전원이 갑자기 꺼져도 내용이 디스크에 남도록 이름을 바꾸기 전에 내려 쓴다.
      try handle.synchronize()
    } catch {
      try? FileManager.default.removeItem(at: temp)
      throw ProjectError.writeFailed(destination, reason: error.localizedDescription)
    }

    let tempPath = temp.path(percentEncoded: false)
    let destinationPath = destination.path(percentEncoded: false)
    if replacing {
      if rename(tempPath, destinationPath) != 0 {
        let reason = String(cString: strerror(errno))
        try? FileManager.default.removeItem(at: temp)
        throw ProjectError.writeFailed(destination, reason: reason)
      }
    } else {
      // link는 새 이름이 이미 있으면 실패하고, 성공하면 다 쓴 파일이 한 번에 그 이름으로 보인다. 그 뒤 임시 이름만 지운다.
      if link(tempPath, destinationPath) != 0 {
        let code = errno
        try? FileManager.default.removeItem(at: temp)
        if code == EEXIST { throw AlreadyExists() }
        throw ProjectError.writeFailed(destination, reason: String(cString: strerror(code)))
      }
      unlink(tempPath)
    }
  }
}
