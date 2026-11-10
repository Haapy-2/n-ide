import Foundation

/// 원자적 쓰기: 같은 폴더의 임시 파일에 끝까지 쓰고 디스크에 확실히 내린 뒤, 한 번의 이름 바꾸기로 교체한다.
/// 이름 바꾸기는 운영체제가 한 번에 처리하므로, 도중에 앱이 죽어도 원래 파일이나 새 파일 중 하나만 남고
/// 반쯤 쓰인 파일은 생기지 않는다.
enum AtomicFile {
  static func write(_ data: Data, to destination: URL) throws {
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

    if rename(temp.path(percentEncoded: false), destination.path(percentEncoded: false)) != 0 {
      let reason = String(cString: strerror(errno))
      try? FileManager.default.removeItem(at: temp)
      throw ProjectError.writeFailed(destination, reason: reason)
    }
  }
}
