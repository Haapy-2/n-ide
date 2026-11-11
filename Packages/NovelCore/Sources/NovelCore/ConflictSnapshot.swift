import Foundation

extension ProjectStore {
  /// 외부 변경과 충돌했을 때 본문을 `snapshots/<회차ID>/<시각>-<label>.md`로 남긴다.
  /// 앱 쪽 본문은 묻기 전에 "conflict"로, 사용자가 앱 쪽을 골라 바깥 내용을 덮어쓸 때는 그 바깥 내용을 "external"로 남긴다.
  /// 사용자가 어느 쪽을 고르든 다른 쪽 원고가 사라지지 않게 하려는 안전망이다.
  /// 버전 스냅샷 전체(목록·복원·보관 개수)는 11단계에서 만든다. 여기서는 쓰기만 하고 아무것도 지우지 않는다.
  @discardableResult
  public func writeConflictSnapshot(
    _ text: String, episode id: EpisodeID, label: String = "conflict", at date: Date = Date()
  ) throws -> URL {
    let folder = layout.snapshotFolder(id)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let base = "\(Self.snapshotTimeFormatter.string(from: date))-\(label)"
    // 같은 초에 두 번 생기면 뒤에 번호를 붙인다. 이미 있는 스냅샷은 덮어쓰지 않는다.
    var url = folder.appending(path: "\(base).md", directoryHint: .notDirectory)
    var number = 2
    while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      url = folder.appending(path: "\(base)-\(number).md", directoryHint: .notDirectory)
      number += 1
    }
    try AtomicFile.write(Data(text.utf8), to: url)
    return url
  }

  /// 파일 이름용 시각. 이름순 정렬이 시간순이 되도록 자릿수를 고정한다(예: 20261111-094512). 이 기기의 시간대 기준.
  private static var snapshotTimeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }
}
