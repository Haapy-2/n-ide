import Foundation

/// Snapshot kind. Goes verbatim at the end of the file name (`<time>-<kind>.md`).
public enum SnapshotKind: String, Sendable, CaseIterable {
  /// Taken manually (⌥⌘S)
  case manual
  /// Every configured interval
  case auto
  /// On leaving an episode (switch, window close, quit)
  case leave
  /// Body right before a restore
  case restore
  /// App-side body on an external-change conflict
  case conflict
  /// External body overwritten when the app side was chosen in a conflict
  case external
  /// Body right before project-wide replace
  case replace
  /// Body right after project-wide replace. Paired with `replace`, it records what that replace changed.
  case replaced
  /// Body right before reverting (or redoing) replace all. Redo uses it to locate the reverted spots.
  case revert
  /// Body when an episode is renamed. The old title is kept in `.title` so restoring brings the title back too.
  /// A record, so pruned by keep count even with a memo. Protected only when `.keep` exists.
  case rename
  /// Body right before entering same-word multi-cursor (⌘D). Named explicitly to keep uppercase out of file names.
  case multiCursor = "multicursor"

  /// Kinds that may be deleted beyond the keep count. An allowlist naming each deletable kind,
  /// so kinds added later aren't deleted unless listed here.
  public var isPrunable: Bool {
    switch self {
    case .auto, .leave, .rename, .multiCursor: true
    case .manual, .restore, .conflict, .external, .replace, .replaced, .revert: false
    }
  }

  /// Kinds holding edited text. Not taken if equal to the last snapshot; if it failed, retaken at the next interval or on leave.
  public var capturesEdits: Bool { self == .auto || self == .leave }
}

/// One snapshot. Built directly from the file name, no index file (the body is read separately with `readSnapshot`).
public struct Snapshot: Hashable, Sendable, Identifiable {
  public let episodeID: EpisodeID
  public let kind: SnapshotKind
  /// Time from the file name (second resolution)
  public let date: Date
  public let url: URL
  /// Number appended when taken again at the same second and kind (the first is 1)
  let sequence: Int
  /// `yyyyMMdd-HHmmss` for sorting
  let stamp: String

  public var id: String { url.lastPathComponent }
  /// The memo lives in a same-named `.memo` file so it doesn't mix with the body (and never enters the body on restore).
  var memoURL: URL { url.deletingPathExtension().appendingPathExtension("memo") }
  var titleURL: URL { url.deletingPathExtension().appendingPathExtension("title") }
  var keepURL: URL { url.deletingPathExtension().appendingPathExtension("keep") }

  /// Parses `20261111-094512-auto.md`, `20261111-094512-auto-2.md`. nil for unknown shapes (excluded from the list and pruning).
  /// Time is built by slicing digits into a calendar instead of `DateFormatter` (`DateFormatter` costs 12.6 ms for a 50-item list).
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
    // Nonexistent times like month 13 or hour 25 are treated as unknown files.
    guard fields.isValidDate(in: calendar), let date = calendar.date(from: fields) else { return nil }
    self.episodeID = episodeID
    self.kind = kind
    self.date = date
    self.url = url
    self.sequence = sequence
    self.stamp = stamp
  }

  /// File name times are in this device's time zone, Gregorian calendar.
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  /// File name time `yyyyMMdd-HHmmss`. Fixed width so name order is time order.
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
  /// Keep the body as `snapshots/<episodeID>/<time>-<kind>.md`. Existing snapshots are never overwritten; same-second ones get `-2`, `-3`.
  /// With `skipIfSameAsLatest`, nothing is taken (returns nil) when content equals the latest snapshot (any kind).
  /// A non-empty memo is written to a same-named `.memo` too. The body is written first, so it survives a failed memo write.
  /// `title` is the episode title at that time (`.title`, written even if empty). Order is body → title → memo, so earlier parts survive later failures.
  /// `fullSync` is as in `AtomicFile.write`: off only where the body is written with F_FULLFSYNC right after (replace all).
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
    // Start after the highest number for the same second and kind. Reusing an earlier number freed by pruning would sort the new snapshot as oldest
    // and get it pruned immediately.
    var number = (try snapshots(of: id).filter { $0.stamp == stamp && $0.kind == kind }.map(\.sequence).max() ?? 0) + 1
    // If the name exists, take the next number. Even if another writer (a conflict snapshot etc.) uses the same name at the same moment, neither overwrites the other.
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

  /// Episode title when the snapshot was taken. Present only on rename snapshots.
  public func readTitle(_ snapshot: Snapshot) -> String? {
    guard Self.isRegularFile(snapshot.titleURL),
      let data = FileManager.default.contents(atPath: snapshot.titleURL.path(percentEncoded: false))
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Mark as exempt from keep-count pruning (rename snapshots). Other kinds are protected by a memo.
  /// Write the mark first, then check the body still exists: pruning checks the mark right before deleting, so if it was already deleted meanwhile,
  /// withdraw the mark and return false.
  @discardableResult
  public func keep(_ snapshot: Snapshot) throws -> Bool {
    try AtomicFile.write(Data(), to: snapshot.keepURL)
    guard Self.isRegularFile(snapshot.url) else {
      try? FileManager.default.removeItem(at: snapshot.keepURL)
      return false
    }
    return true
  }

  /// Whether it's exempt from keep-count pruning. For renames `.keep` is the mark, for others the memo.
  public func isKept(_ snapshot: Snapshot) -> Bool {
    Self.isRegularFile(snapshot.kind == .rename ? snapshot.keepURL : snapshot.memoURL)
  }

  /// One episode's snapshot list, oldest first. Only file names are read. Empty list if the folder is missing.
  public func snapshots(of id: EpisodeID) throws -> [Snapshot] {
    let folder = layout.snapshotFolder(id)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    let calendar = Snapshot.calendar
    // Folders or aliases merely named like snapshots aren't listed (they can't be read, and pruning must not delete them).
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

  /// Check whether the item there is a regular file without following aliases (symbolic links).
  private static func isRegularFile(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path(percentEncoded: false), &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
  }

  /// nil if there's no memo.
  public func readMemo(_ snapshot: Snapshot) -> String? {
    guard let data = FileManager.default.contents(atPath: snapshot.memoURL.path(percentEncoded: false)) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Trim surrounding whitespace before writing. An empty memo removes the memo file (the body snapshot stays).
  public func writeMemo(_ memo: String, for snapshot: Snapshot, fullSync: Bool = true) throws {
    let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      let path = snapshot.memoURL.path(percentEncoded: false)
      if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
    } else {
      try AtomicFile.write(Data(trimmed.utf8), to: snapshot.memoURL, fullSync: fullSync)
    }
  }

  /// Count `auto`·`leave`·`rename`·`multicursor` together and delete the oldest beyond `limit` immediately (not to Trash). Returns the deleted list.
  /// Other kinds and unknown files are neither counted nor deleted. Protected ones (`isKept`) are neither counted nor deleted either.
  @discardableResult
  public func pruneSnapshots(of id: EpisodeID, keeping limit: Int) throws -> [Snapshot] {
    let prunable = try snapshots(of: id).filter { $0.kind.isPrunable && !isKept($0) }
    // Keep at least one so a value ≤ 0 never deletes everything.
    let excess = prunable.count - max(limit, 1)
    guard excess > 0 else { return [] }
    let removed = Array(prunable.prefix(excess))
    var done: [Snapshot] = []
    for snapshot in removed {
      // Already filtered in the list, but it may have changed since, so check once more right before deleting (deleting a folder removes everything inside).
      // Skip if it became protected meanwhile (e.g. right after a memo was added in the panel).
      guard Self.isRegularFile(snapshot.url), !isKept(snapshot) else { continue }
      // Delete companion files first. If interrupted, what remains is the body visible in the list, which the next prune finishes.
      for sidecar in [snapshot.memoURL, snapshot.titleURL] where Self.isRegularFile(sidecar) {
        try FileManager.default.removeItem(at: sidecar)
      }
      try FileManager.default.removeItem(at: snapshot.url)
      done.append(snapshot)
    }
    return done
  }
}
