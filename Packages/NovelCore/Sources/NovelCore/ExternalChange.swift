import Foundation

/// 파일의 수정 시각과 크기. 외부 변경을 값싸게 1차로 가려내는 데 쓴다(PLAN 5장 "외부 변경 감지").
public struct FileStamp: Equatable, Sendable {
  public let modified: Date
  public let size: Int

  public init(modified: Date, size: Int) {
    self.modified = modified
    self.size = size
  }

  /// 파일이 없거나 정보를 읽을 수 없으면 nil.
  public init?(of url: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
      let modified = attributes[.modificationDate] as? Date,
      let size = attributes[.size] as? Int
    else { return nil }
    self.init(modified: modified, size: size)
  }
}

/// 앱이 회차 파일을 마지막으로 읽거나 쓴 때의 디스크 상태. 다음 확인 때 이것과 비교한다.
public struct DiskVersion: Equatable, Sendable {
  /// nil이면 시각·크기를 믿을 수 없다는 뜻이라 다음 확인 때 내용을 바로 비교한다.
  public let stamp: FileStamp?
  public let text: String

  public init(stamp: FileStamp?, text: String) {
    self.stamp = stamp
    self.text = text
  }
}

/// 외부 변경 확인 결과.
public enum DiskCheck: Equatable, Sendable {
  /// 내용이 그대로다. 시각만 바뀌었으면(내용이 같은 저장) 새 시각을 담은 상태를 돌려준다.
  case unchanged(DiskVersion)
  /// 앱 밖에서 내용이 바뀌었다.
  case changed(DiskVersion)
  /// 파일이 없어졌다.
  case missing
}

/// 외부 변경을 확인하며 쓴 결과.
public enum EpisodeWriteResult: Equatable, Sendable {
  case written(DiskVersion)
  /// 앱 밖에서 바뀌어 있어서 쓰지 않았다. 디스크의 지금 상태를 담는다.
  case conflict(DiskVersion)
}

extension ProjectStore {
  /// 회차 본문과 그 순간의 파일 상태를 함께 읽는다.
  public func readEpisodeVersion(_ id: EpisodeID) throws -> DiskVersion {
    let url = layout.episodeFile(id)
    // 시각을 먼저 읽고 내용을 나중에 읽는다. 그 사이에 누가 고치면 "옛 시각 + 새 내용"이 되는데,
    // 그러면 다음 확인 때 시각이 달라 내용을 다시 비교하므로 변경을 놓치지 않는다(반대 순서면 놓칠 수 있다).
    let stamp = FileStamp(of: url)
    return DiskVersion(stamp: stamp, text: try readText(at: url))
  }

  /// 회차 파일이 `known` 이후 앱 밖에서 바뀌었는지 본다.
  /// 시각·크기가 같으면 파일을 읽지 않는다. 다르면 내용까지 비교해, 내용이 같으면(다른 앱이 저장만 다시 한 경우) 바뀌지 않은 것으로 본다.
  public func checkEpisode(_ id: EpisodeID, against known: DiskVersion) throws -> DiskCheck {
    let url = layout.episodeFile(id)
    guard let stamp = FileStamp(of: url) else { return .missing }
    if let knownStamp = known.stamp, knownStamp == stamp { return .unchanged(known) }
    let current = DiskVersion(stamp: stamp, text: try readText(at: url))
    return current.text == known.text ? .unchanged(current) : .changed(current)
  }

  /// 저장 직전 확인 + 쓰기. `known` 이후 앱 밖에서 바뀌었으면 쓰지 않고 `.conflict`를 돌려준다.
  /// `known`이 nil이거나 파일이 없어졌으면 그냥 쓴다(없어진 본문은 앱의 내용으로 되살리는 편이 안전하다).
  public func writeEpisode(_ text: String, id: EpisodeID, ifUnchangedSince known: DiskVersion?) throws
    -> EpisodeWriteResult
  {
    if let known, case .changed(let disk) = try checkEpisode(id, against: known) {
      return .conflict(disk)
    }
    let data = Data(text.utf8)
    let url = layout.episodeFile(id)
    try AtomicFile.write(data, to: url)
    var stamp = FileStamp(of: url)
    // 쓰고 나서 시각을 읽기 직전에 다른 앱이 또 썼다면 크기가 다를 수 있다. 그때는 시각을 믿지 않고 다음에 내용을 비교한다.
    if stamp?.size != data.count { stamp = nil }
    return .written(DiskVersion(stamp: stamp, text: text))
  }
}
