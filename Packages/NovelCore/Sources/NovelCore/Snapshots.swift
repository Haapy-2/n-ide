import Foundation

/// 스냅샷 종류. 파일 이름 끝(`<시각>-<종류>.md`)에 그대로 들어간다.
public enum SnapshotKind: String, Sendable, CaseIterable {
  /// 직접 찍음(⌥⌘S)
  case manual
  /// 설정한 간격마다
  case auto
  /// 회차를 떠날 때(전환·창 닫기·앱 종료)
  case leave
  /// 복원 직전의 본문
  case restore
  /// 외부 변경과 충돌했을 때 앱 쪽 본문
  case conflict
  /// 충돌에서 앱 쪽을 골라 덮어쓴 바깥 본문
  case external

  /// 보관 개수를 넘으면 지워도 되는 종류. 지울 수 있는 것을 하나씩 적는 허용 목록이라,
  /// 나중에 종류가 늘어도 여기에 적지 않으면 지워지지 않는다.
  public var isPrunable: Bool {
    switch self {
    case .auto, .leave: true
    case .manual, .restore, .conflict, .external: false
    }
  }
}

/// 스냅샷 하나. 목록 파일 없이 파일 이름에서 바로 만든다(본문은 `readSnapshot`으로 따로 읽는다).
public struct Snapshot: Hashable, Sendable, Identifiable {
  public let episodeID: EpisodeID
  public let kind: SnapshotKind
  /// 파일 이름의 시각(초 단위)
  public let date: Date
  public let url: URL
  /// 같은 초·같은 종류로 또 찍었을 때 붙는 번호(처음 것은 1)
  let sequence: Int
  /// 정렬용 `yyyyMMdd-HHmmss`
  let stamp: String

  public var id: String { url.lastPathComponent }
  /// 메모는 본문과 섞이지 않게 같은 이름의 `.memo` 파일에 둔다(복원할 때 본문에 들어가지 않도록).
  var memoURL: URL { url.deletingPathExtension().appendingPathExtension("memo") }

  /// `20261111-094512-auto.md`, `20261111-094512-auto-2.md`를 읽는다. 모르는 모양이면 nil(목록에도 정리에도 안 잡힘).
  /// 시각은 `DateFormatter` 대신 숫자를 직접 잘라 달력으로 만든다(측정: 50개 목록 12.6ms → 아래 값, docs/log/log26-11-17.md).
  init?(url: URL, episodeID: EpisodeID, calendar: Calendar = Snapshot.calendar) {
    let name = url.lastPathComponent
    guard !name.hasPrefix("."), url.pathExtension == "md" else { return nil }
    let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3 || parts.count == 4,
      parts[0].count == 8, parts[1].count == 6,
      parts[0].allSatisfy(\.isASCIIDigit), parts[1].allSatisfy(\.isASCIIDigit),
      let kind = SnapshotKind(rawValue: String(parts[2]))
    else { return nil }
    var sequence = 1
    if parts.count == 4 {
      guard let number = Int(parts[3]), number >= 2 else { return nil }
      sequence = number
    }
    let stamp = "\(parts[0])-\(parts[1])"
    let digits = Array(parts[0].utf8) + Array(parts[1].utf8)
    func number(_ range: Range<Int>) -> Int { digits[range].reduce(0) { $0 * 10 + Int($1 - 48) } }
    let fields = DateComponents(
      year: number(0..<4), month: number(4..<6), day: number(6..<8),
      hour: number(8..<10), minute: number(10..<12), second: number(12..<14))
    // 13월, 25시 같은 없는 시각은 모르는 파일로 본다.
    guard fields.isValidDate(in: calendar), let date = calendar.date(from: fields) else { return nil }
    self.episodeID = episodeID
    self.kind = kind
    self.date = date
    self.url = url
    self.sequence = sequence
    self.stamp = stamp
  }

  /// 파일 이름의 시각은 이 기기의 시간대 기준, 양력.
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  /// 파일 이름용 시각 `yyyyMMdd-HHmmss`. 이름순이 시간순이 되도록 자릿수를 고정한다.
  static func stamp(for date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    func pad(_ value: Int?, _ width: Int) -> String {
      let text = String(value ?? 0)
      return String(repeating: "0", count: max(0, width - text.count)) + text
    }
    return "\(pad(c.year, 4))\(pad(c.month, 2))\(pad(c.day, 2))-\(pad(c.hour, 2))\(pad(c.minute, 2))\(pad(c.second, 2))"
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

extension ProjectStore {
  /// 본문을 `snapshots/<회차ID>/<시각>-<종류>.md`로 남긴다. 이미 있는 스냅샷은 덮지 않고 같은 초면 `-2`, `-3`을 붙인다.
  /// `skipIfSameAsLatest`이면 가장 최근 스냅샷(종류 무관)과 내용이 같을 때 찍지 않고 nil을 돌려준다.
  /// 메모가 비어 있지 않으면 같은 이름의 `.memo`에 함께 쓴다. 본문을 먼저 써서, 메모 쓰기가 실패해도 본문은 남는다.
  @discardableResult
  public func writeSnapshot(
    _ text: String, episode id: EpisodeID, kind: SnapshotKind, memo: String? = nil,
    at date: Date = Date(), skipIfSameAsLatest: Bool = false
  ) throws -> Snapshot? {
    if skipIfSameAsLatest, let latest = try snapshots(of: id).last, try readSnapshot(latest) == text {
      return nil
    }
    let folder = layout.snapshotFolder(id)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let base = "\(Snapshot.stamp(for: date))-\(kind.rawValue)"
    var url = folder.appending(path: "\(base).md", directoryHint: .notDirectory)
    var number = 2
    while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      url = folder.appending(path: "\(base)-\(number).md", directoryHint: .notDirectory)
      number += 1
    }
    try AtomicFile.write(Data(text.utf8), to: url)
    guard let snapshot = Snapshot(url: url, episodeID: id) else {
      throw ProjectError.writeFailed(url, reason: "스냅샷 이름을 읽을 수 없음")
    }
    if let memo { try writeMemo(memo, for: snapshot) }
    return snapshot
  }

  /// 한 회차의 스냅샷 목록, 오래된 것부터. 파일 이름만 읽는다. 폴더가 없으면 빈 목록.
  public func snapshots(of id: EpisodeID) throws -> [Snapshot] {
    let folder = layout.snapshotFolder(id)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    let calendar = Snapshot.calendar
    return urls.compactMap { Snapshot(url: $0, episodeID: id, calendar: calendar) }.sorted {
      ($0.stamp, $0.sequence, $0.kind.rawValue) < ($1.stamp, $1.sequence, $1.kind.rawValue)
    }
  }

  public func readSnapshot(_ snapshot: Snapshot) throws -> String {
    guard let data = FileManager.default.contents(atPath: snapshot.url.path(percentEncoded: false)) else {
      throw ProjectError.missingTextFile(snapshot.url)
    }
    guard let text = String(data: data, encoding: .utf8) else { throw ProjectError.notUTF8(snapshot.url) }
    return text
  }

  /// 메모가 없으면 nil.
  public func readMemo(_ snapshot: Snapshot) -> String? {
    guard let data = FileManager.default.contents(atPath: snapshot.memoURL.path(percentEncoded: false)) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// 앞뒤 공백을 다듬어 쓴다. 비우면 메모 파일을 없앤다(본문 스냅샷은 그대로).
  public func writeMemo(_ memo: String, for snapshot: Snapshot) throws {
    let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      let path = snapshot.memoURL.path(percentEncoded: false)
      if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
    } else {
      try AtomicFile.write(Data(trimmed.utf8), to: snapshot.memoURL)
    }
  }

  /// `auto`·`leave`만 함께 세어 `limit`개를 넘으면 오래된 것부터 바로 지운다(휴지통 아님). 지운 목록을 돌려준다.
  /// 다른 종류와 모르는 파일은 세지도 지우지도 않는다. 지운 스냅샷에 메모가 있었다면 메모도 함께 지운다.
  @discardableResult
  public func pruneSnapshots(of id: EpisodeID, keeping limit: Int) throws -> [Snapshot] {
    let prunable = try snapshots(of: id).filter(\.kind.isPrunable)
    // 0 이하가 들어와도 전부 지우지 않도록 적어도 하나는 남긴다.
    let excess = prunable.count - max(limit, 1)
    guard excess > 0 else { return [] }
    let removed = Array(prunable.prefix(excess))
    for snapshot in removed {
      try FileManager.default.removeItem(at: snapshot.url)
      let memo = snapshot.memoURL.path(percentEncoded: false)
      if FileManager.default.fileExists(atPath: memo) { try? FileManager.default.removeItem(atPath: memo) }
    }
    return removed
  }
}
