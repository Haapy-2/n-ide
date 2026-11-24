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
  /// 작품 전체 바꾸기 직전의 본문
  case replace
  /// 작품 전체 바꾸기 직후의 본문. `replace`와 짝으로 그 바꾸기가 무엇을 바꿨는지 남는다.
  case replaced
  /// 전체 바꾸기를 되돌리기(또는 다시 바꾸기) 직전의 본문. 다시 바꾸기가 이것으로 되돌린 자리를 알아낸다.
  case revert
  /// 회차 이름이 바뀔 때의 본문. 바뀌기 전 제목을 `.title`에 함께 둬서 복원하면 제목도 돌아간다.
  /// 기록용이라 메모가 있어도 보관 개수로 지운다. `.keep`이 있을 때만 지킨다.
  case rename

  /// 보관 개수를 넘으면 지워도 되는 종류. 지울 수 있는 것을 하나씩 적는 허용 목록이라,
  /// 나중에 종류가 늘어도 여기에 적지 않으면 지워지지 않는다.
  public var isPrunable: Bool {
    switch self {
    case .auto, .leave, .rename: true
    case .manual, .restore, .conflict, .external, .replace, .replaced, .revert: false
    }
  }

  /// 고친 글을 담는 종류. 마지막 스냅샷과 같으면 찍지 않고, 못 찍었으면 다음 간격이나 떠날 때 다시 찍는다.
  public var capturesEdits: Bool { self == .auto || self == .leave }
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
  var titleURL: URL { url.deletingPathExtension().appendingPathExtension("title") }
  var keepURL: URL { url.deletingPathExtension().appendingPathExtension("keep") }

  /// `20261111-094512-auto.md`, `20261111-094512-auto-2.md`를 읽는다. 모르는 모양이면 nil(목록에도 정리에도 안 잡힘).
  /// 시각은 `DateFormatter` 대신 숫자를 직접 잘라 달력으로 만든다(`DateFormatter`는 50개 목록에 12.6ms).
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
  /// `title`은 그때의 회차 제목(`.title`, 빈 제목도 쓴다). 본문 → 제목 → 메모 순서라 뒤가 실패해도 앞은 남는다.
  /// `fullSync`는 `AtomicFile.write`와 같다: 바로 뒤에 본문을 F_FULLFSYNC로 쓰는 곳(전체 바꾸기)에서만 끈다.
  @discardableResult
  public func writeSnapshot(
    _ text: String, episode id: EpisodeID, kind: SnapshotKind, memo: String? = nil, title: String? = nil,
    at date: Date = Date(), skipIfSameAsLatest: Bool = false, fullSync: Bool = true
  ) throws -> Snapshot? {
    if skipIfSameAsLatest, let latest = try snapshots(of: id).last, try readSnapshot(latest) == text {
      return nil
    }
    let folder = layout.snapshotFolder(id)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stamp = Snapshot.stamp(for: date)
    let base = "\(stamp)-\(kind.rawValue)"
    let data = Data(text.utf8)
    // 같은 초·같은 종류의 가장 큰 번호 다음부터. 정리로 지워진 앞 번호를 다시 쓰면 새 스냅샷이 가장 오래된 것으로
    // 정렬되어 곧바로 정리된다.
    var number = (try snapshots(of: id).filter { $0.stamp == stamp && $0.kind == kind }.map(\.sequence).max() ?? 0) + 1
    // 이름이 있으면 다음 번호로. 같은 순간에 다른 곳(충돌 스냅샷 등)이 같은 이름을 써도 서로 덮지 않는다.
    while true {
      let name = number == 1 ? "\(base).md" : "\(base)-\(number).md"
      let url = folder.appending(path: name, directoryHint: .notDirectory)
      do {
        try AtomicFile.write(data, to: url, replacing: false, fullSync: fullSync)
        break
      } catch is AtomicFile.AlreadyExists {
        number += 1
      }
    }
    let url = folder.appending(path: number == 1 ? "\(base).md" : "\(base)-\(number).md", directoryHint: .notDirectory)
    guard let snapshot = Snapshot(url: url, episodeID: id) else {
      throw ProjectError.writeFailed(url, reason: "스냅샷 이름을 읽을 수 없음")
    }
    if let title { try AtomicFile.write(Data(title.utf8), to: snapshot.titleURL, fullSync: fullSync) }
    if let memo { try writeMemo(memo, for: snapshot, fullSync: fullSync) }
    return snapshot
  }

  /// 스냅샷을 찍을 때의 회차 제목. 이름 변경 스냅샷에만 있다.
  public func readTitle(_ snapshot: Snapshot) -> String? {
    guard Self.isRegularFile(snapshot.titleURL),
      let data = FileManager.default.contents(atPath: snapshot.titleURL.path(percentEncoded: false))
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// 보관 개수로 지우지 않게 표시한다(이름 변경 스냅샷). 다른 종류는 메모로 지킨다.
  public func keep(_ snapshot: Snapshot) throws {
    try AtomicFile.write(Data(), to: snapshot.keepURL)
  }

  /// 보관 개수로 지우지 않는 것인지. 이름 변경은 `.keep`, 나머지는 메모가 그 표시다.
  public func isKept(_ snapshot: Snapshot) -> Bool {
    Self.isRegularFile(snapshot.kind == .rename ? snapshot.keepURL : snapshot.memoURL)
  }

  /// 한 회차의 스냅샷 목록, 오래된 것부터. 파일 이름만 읽는다. 폴더가 없으면 빈 목록.
  public func snapshots(of id: EpisodeID) throws -> [Snapshot] {
    let folder = layout.snapshotFolder(id)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    let calendar = Snapshot.calendar
    // 이름만 스냅샷처럼 생긴 폴더·바로가기는 목록에 넣지 않는다(읽을 수도 없고, 정리가 지우면 안 된다).
    return urls.compactMap { url in
      Snapshot(url: url, episodeID: id, calendar: calendar).flatMap { Self.isRegularFile(url) ? $0 : nil }
    }.sorted {
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

  /// 바로가기(심볼릭 링크)를 따라가지 않고 그 자리의 것이 보통 파일인지 본다.
  private static func isRegularFile(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path(percentEncoded: false), &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
  }

  /// 메모가 없으면 nil.
  public func readMemo(_ snapshot: Snapshot) -> String? {
    guard let data = FileManager.default.contents(atPath: snapshot.memoURL.path(percentEncoded: false)) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// 앞뒤 공백을 다듬어 쓴다. 비우면 메모 파일을 없앤다(본문 스냅샷은 그대로).
  public func writeMemo(_ memo: String, for snapshot: Snapshot, fullSync: Bool = true) throws {
    let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      let path = snapshot.memoURL.path(percentEncoded: false)
      if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
    } else {
      try AtomicFile.write(Data(trimmed.utf8), to: snapshot.memoURL, fullSync: fullSync)
    }
  }

  /// `auto`·`leave`·`rename`을 함께 세어 `limit`개를 넘으면 오래된 것부터 바로 지운다(휴지통 아님). 지운 목록을 돌려준다.
  /// 다른 종류와 모르는 파일은 세지도 지우지도 않는다. 지키기로 한 것(`isKept`)도 세지도 지우지도 않는다.
  @discardableResult
  public func pruneSnapshots(of id: EpisodeID, keeping limit: Int) throws -> [Snapshot] {
    let prunable = try snapshots(of: id).filter { $0.kind.isPrunable && !isKept($0) }
    // 0 이하가 들어와도 전부 지우지 않도록 적어도 하나는 남긴다.
    let excess = prunable.count - max(limit, 1)
    guard excess > 0 else { return [] }
    let removed = Array(prunable.prefix(excess))
    var done: [Snapshot] = []
    for snapshot in removed {
      // 목록에서 이미 걸렀지만, 그 사이에 바뀌었을 수 있어 지우기 직전에 한 번 더 본다(폴더를 지우면 안의 것이 통째로 사라진다).
      // 그사이 지키기로 했으면(판에서 메모를 단 직후 등) 건너뛴다.
      guard Self.isRegularFile(snapshot.url), !isKept(snapshot) else { continue }
      // 딸린 파일을 먼저 지운다. 도중에 멈춰도 남는 것은 목록에 보이는 본문이라 다음 정리가 마저 지운다.
      for sidecar in [snapshot.memoURL, snapshot.titleURL] where Self.isRegularFile(sidecar) {
        try FileManager.default.removeItem(at: sidecar)
      }
      try FileManager.default.removeItem(at: snapshot.url)
      done.append(snapshot)
    }
    return done
  }
}
