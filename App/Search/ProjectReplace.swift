import Foundation
import NovelCore
import Observation

/// Project-wide replace (PLAN ch.14). `모두 바꾸기` recounts fully (`prepare`), and on confirmation replaces per episode (`confirm`).
/// Search results are capped at 1,000, so the confirmation's number is the recount, not the search result.
@MainActor
@Observable
final class ProjectReplace {
  /// Undo action name for editor and window. If the window's ⌘Z has this name, the revert sheet opens without asking.
  static let actionName = "전체 바꾸기"
  /// A replace awaiting confirmation. Execution is based on the text counted at this time.
  struct Pending {
    let plan: ReplacementPlan
    let query: String
    let replacement: String
    let caseSensitive: Bool

    var title: String {
      let episodes = plan.episodes.count.formatted()
      let places = plan.count.formatted()
      return replacement.isEmpty
        ? "\(episodes)개 회차에서 '\(query)' \(places)곳을 지울까요?"
        : "\(episodes)개 회차에서 \(places)곳을 \(KoreanParticle.attach(.direction, to: "'\(replacement)'")) 바꿀까요?"
    }

    var message: String {
      var lines = ["바꾸기 전 글은 회차마다 스냅샷으로 남겨요."]
      if !plan.unreadable.isEmpty { lines.append("읽지 못한 회차 \(plan.unreadable.count)개는 바꾸지 않아요.") }
      return lines.joined(separator: "\n")
    }

    /// Snapshot memo
    var memo: String {
      replacement.isEmpty ? "'\(query)' 모두 지우기" : "'\(query)' → '\(replacement)' 전체 바꾸기"
    }
  }

  /// Result of a finished replace
  struct Report: Equatable {
    struct Episode: Equatable {
      let id: EpisodeID
      /// Spots replaced in this episode (based on the text at replace time)
      let count: Int
      let before: Snapshot?
    }

    var query = ""
    var replacement = ""
    /// Replaced episodes, in replace order (the open episode last)
    var replaced: [Episode] = []
    /// Episodes waiting on an external-change conflict
    var conflicted = 0
    /// Episodes whose pre-replace snapshot couldn't be taken
    var snapshotFailed = 0
    /// Episodes changed outside the app repeatedly between read and write
    var keptChanging = 0
    /// Episodes whose body couldn't be read
    var unreadable = 0

    var count: Int { replaced.reduce(0) { $0 + $1.count } }
    var skipped: Int { conflicted + snapshotFailed + keptChanging }
  }

  /// One revertible replace all (PLAN ch.14 #5). Kept in memory only while the window is open (snapshot locations only, no bodies).
  struct Record: Identifiable, Equatable {
    struct Entry: Equatable {
      let id: EpisodeID
      /// `바꾸기 전` snapshot. On revert, the same replace is reapplied to this text to locate the replaced spots.
      let before: Snapshot
    }

    let id = UUID()
    let query: String
    let replacement: String
    let caseSensitive: Bool
    let date: Date
    /// Leading part of the snapshot memo (`'민준' → '도윤' 전체 바꾸기`)
    let memo: String
    /// Replaced episodes, in episode order
    let entries: [Entry]
    /// Number of replaced spots (revert sheet header)
    let count: Int
  }

  /// One row of the revert sheet: an episode that still has spots that would actually change if reverted now
  struct Candidate: Identifiable, Equatable {
    let id: EpisodeID
    /// Spots to revert
    let count: Int
    /// Spots edited since, to leave alone
    let kept: Int
  }

  /// What was re-detected when opening the revert sheet
  struct Undoable {
    let record: Record
    let candidates: [Candidate]
    /// Episodes dropped from the list because already reverted or all replaced spots were edited
    let excluded: Int
    /// Episodes that can't be reverted because the pre-replace snapshot or body is unreadable (deleted in the snapshot panel or read error)
    let unreadable: Int
  }

  /// Just-reverted episodes. Redo replace covers only these, locating reverted spots via the text right before the revert (`되돌리기 전` snapshot).
  struct Reverted {
    struct Entry {
      let id: EpisodeID
      let before: Snapshot
      let revertedFrom: Snapshot
    }

    let record: Record
    let entries: [Entry]
  }

  /// Result of revert / redo replace
  struct RevertReport: Equatable {
    var episodes = 0
    var count = 0
    var kept = 0
    var skipped = 0
    var unreadable = 0
  }

  var replacement = ""
  private(set) var pending: Pending?
  /// Counting or replacing. Buttons are disabled meanwhile.
  private(set) var isWorking = false
  /// Last finished replace. The search panel shows it as the replaced-episodes list; cleared when the query changes or the panel closes.
  private(set) var finished: Report?
  /// Revertible replaces, oldest first. Revert goes newest first.
  private(set) var history: [Record] = []
  /// A revert awaiting redo
  private(set) var reverted: Reverted?

  @ObservationIgnored private let store: ProjectStore
  @ObservationIgnored private let autosaver: EpisodeAutosaver
  @ObservationIgnored private let episodeIDs: () -> [EpisodeID]
  @ObservationIgnored private let recordCount: (CharacterCount, EpisodeID) -> Void

  init(
    store: ProjectStore, autosaver: EpisodeAutosaver, episodeIDs: @escaping () -> [EpisodeID],
    recordCount: @escaping (CharacterCount, EpisodeID) -> Void
  ) {
    self.store = store
    self.autosaver = autosaver
    self.episodeIDs = episodeIDs
    self.recordCount = recordCount
  }

  /// Count fully off the main thread. If there are spots to replace, `pending` is filled and the confirmation appears.
  func prepare(query: String, caseSensitive: Bool) async {
    let replacement = replacement
    guard !isWorking, pending == nil, TextReplace.canReplace(query, with: replacement) else { return }
    isWorking = true
    defer { isWorking = false }
    let ids = episodeIDs()
    let texts = autosaver.searchTexts()
    let store = store
    let plan = try? await Task.detached(priority: .userInitiated) {
      try store.replacementPlan(query, in: ids, texts: texts, caseSensitive: caseSensitive)
    }.value
    guard let plan, !plan.episodes.isEmpty else { return }
    pending = Pending(plan: plan, query: query, replacement: replacement, caseSensitive: caseSensitive)
  }

  func cancel() {
    pending = nil
  }

  /// Replace was chosen in the confirmation. Re-find in each episode's current text, snapshot, then replace. nil if already replacing.
  /// The confirmation closes as soon as a button is pressed and clears `pending`, so execute what the dialog showed.
  func confirm(_ pending: Pending) async -> Report? {
    guard !isWorking else { return nil }
    self.pending = nil
    isWorking = true
    defer { isWorking = false }
    let date = Date()
    let replacement = EpisodeAutosaver.Rewrite.replace(
      query: pending.query, replacement: pending.replacement, caseSensitive: pending.caseSensitive, date: date,
      memo: pending.memo)
    var report = Report(query: pending.query, replacement: pending.replacement, unreadable: pending.plan.unreadable.count)
    await rewriteEach(pending.plan.episodes.map(\.id), { _ in replacement }) { id, outcome in
      tally(outcome, for: id, into: &report)
    }
    // The replaced-episodes list is in episode order (replace order puts the open episode last, which reads oddly as a list).
    let order = Dictionary(uniqueKeysWithValues: pending.plan.episodes.enumerated().map { ($1.id, $0) })
    finished = Report(
      query: report.query, replacement: report.replacement,
      replaced: report.replaced.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] },
      conflicted: report.conflicted, snapshotFailed: report.snapshotFailed, keptChanging: report.keptChanging,
      unreadable: report.unreadable)
    let entries = finished?.replaced.compactMap { entry in entry.before.map { Record.Entry(id: entry.id, before: $0) } } ?? []
    if !entries.isEmpty {
      history.append(
        Record(
          query: pending.query, replacement: pending.replacement, caseSensitive: pending.caseSensitive, date: date,
          memo: pending.memo, entries: entries, count: report.count))
      reverted = nil
    }
    return report
  }

  /// Rewrite each episode and report as each finishes. The open episode goes separately at the end: while waiting for composition to end there,
  /// other episodes finish first. The rest run a few at a time: while one episode flushes its body with F_FULLFSYNC (~3 ms),
  /// the next episode's read/snapshot happens. Per-episode order (pre-edit snapshot → body) is unchanged, and the save queue writes bodies one at a time.
  /// Episodes trashed after counting aren't reported.
  private func rewriteEach(
    _ ids: [EpisodeID], _ job: (EpisodeID) -> EpisodeAutosaver.Rewrite,
    onDone: (EpisodeID, EpisodeAutosaver.RewriteOutcome) -> Void
  ) async {
    autosaver.beginBulkRewrite()
    defer { autosaver.endBulkRewrite() }
    let open = autosaver.episodeID
    var running: [Task<(EpisodeID, EpisodeAutosaver.RewriteOutcome?), Never>] = []
    func finishFirst() async {
      let (done, outcome) = await running.removeFirst().value
      if let outcome { onDone(done, outcome) }
    }
    for id in ids where id != open {
      let rewrite = job(id)
      running.append(Task { (id, await replaceIfListed(id, rewrite)) })
      if running.count >= Self.overlap { await finishFirst() }
    }
    while !running.isEmpty { await finishFirst() }
    if let open, ids.contains(open), let outcome = await replaceIfListed(open, job(open)) {
      onDone(open, outcome)
    }
  }

  /// Number of episodes replaced concurrently. More doesn't help since bodies are written one at a time; it only uses memory.
  private static let overlap = 8

  /// Writing to an episode trashed after counting would resurrect its deleted body file. The writer deleted it, so it doesn't count as skipped (nil).
  private func replaceIfListed(
    _ id: EpisodeID, _ job: EpisodeAutosaver.Rewrite
  ) async -> EpisodeAutosaver.RewriteOutcome? {
    guard episodeIDs().contains(id) else { return nil }
    return await autosaver.rewrite(id, job)
  }

  private func tally(_ outcome: EpisodeAutosaver.RewriteOutcome, for id: EpisodeID, into report: inout Report) {
    switch outcome {
    case .done(let count, _, let characters, let before):
      report.replaced.append(.init(id: id, count: count, before: before))
      if let characters { recordCount(characters, id) }
    case .nothing: break
    case .conflict: report.conflicted += 1
    case .snapshotFailed: report.snapshotFailed += 1
    case .keptChanging: report.keptChanging += 1
    case .unreadable: report.unreadable += 1
    }
  }

  // MARK: - Revert / redo replace (PLAN ch.14 #5)

  /// Newest replace first, find one that still has spots that would actually change if reverted now. Re-detected per episode in its current text
  /// (dropped from the list if editor ⌘Z already reverted it or all replaced spots were edited). nil if none.
  func latestUndoable() async -> Undoable? {
    for record in history.reversed() {
      let found = await candidates(for: record)
      if !found.candidates.isEmpty { return found }
    }
    return nil
  }

  private func candidates(for record: Record) async -> Undoable {
    let listed = Set(episodeIDs())
    let entries = record.entries.filter { listed.contains($0.id) }
    let texts = autosaver.searchTexts()
    let store = store
    let (candidates, unreadable) = await Task.detached(priority: .userInitiated) {
      var candidates: [Candidate] = []
      var unreadable = 0
      for entry in entries {
        guard let outcome = try? Self.revertOutcome(record, entry.before, current: texts[entry.id], store: store) else {
          unreadable += 1
          continue
        }
        guard !outcome.changes.isEmpty else { continue }
        candidates.append(Candidate(id: entry.id, count: outcome.changes.count, kept: outcome.kept))
      }
      return (candidates, unreadable)
    }.value
    return Undoable(
      record: record, candidates: candidates, excluded: entries.count - candidates.count - unreadable,
      unreadable: unreadable)
  }

  /// One episode's `now → after revert` diff (right side of the revert sheet). Built off the main thread.
  func preview(_ record: Record, _ id: EpisodeID) async -> TextDiff? {
    guard let entry = record.entries.first(where: { $0.id == id }) else { return nil }
    let current = autosaver.searchTexts()[id]
    let store = store
    return try? await Task.detached(priority: .userInitiated) {
      let current = try current ?? store.readEpisode(id)
      let outcome = try Self.revertOutcome(record, entry.before, current: current, store: store)
      return try TextDiff(old: current, new: outcome.text)
    }.value
  }

  nonisolated private static func revertOutcome(
    _ record: Record, _ before: Snapshot, current: String?, store: ProjectStore
  ) throws -> ReplaceRevert.Outcome {
    try ReplaceRevert.reverting(
      record.query, with: record.replacement, caseSensitive: record.caseSensitive, before: store.readSnapshot(before),
      current: current ?? store.readEpisode(before.episodeID))
  }

  /// Revert replaced spots only in the chosen episodes. Unchosen ones are untouched and stay recorded, so reopening the sheet shows only them.
  func revert(_ record: Record, _ ids: Set<EpisodeID>) async -> RevertReport {
    // Do nothing if another replace/revert is running (otherwise only the redo record would be erased).
    guard !isWorking else { return RevertReport() }
    let store = store
    let stamp = Self.stamp(record.date)
    let date = Date()
    let entries = record.entries.filter { ids.contains($0.id) }
    var done: [Reverted.Entry] = []
    let report = await run(entries.map(\.id)) { entry in
      let before = record.entries.first { $0.id == entry }!.before
      return EpisodeAutosaver.Rewrite(
        changes: { text in
          let outcome = try Self.revertOutcome(record, before, current: text, store: store)
          return (outcome.changes, outcome.kept)
        },
        beforeKind: .revert,
        beforeMemo: { count, kept in
          "\(record.memo)(\(stamp)) 되돌림 · \(count)곳" + (kept > 0 ? ", \(kept)곳은 그 뒤에 고쳐 그대로" : "")
        },
        afterMemo: nil, date: date, actionName: "\(Self.actionName) 되돌리기")
    } onDone: { id, snapshot in
      guard let snapshot, let before = record.entries.first(where: { $0.id == id })?.before else { return }
      done.append(.init(id: id, before: before, revertedFrom: snapshot))
    }
    reverted = done.isEmpty ? nil : Reverted(record: record, entries: done)
    return report
  }

  /// Redo the replace the same way on just-reverted episodes only. Takes a new `바꾸기 전` snapshot.
  func redo() async -> RevertReport? {
    guard let reverted, !isWorking else { return nil }
    self.reverted = nil
    let record = reverted.record
    let store = store
    let memo = record.replacement.isEmpty
      ? "'\(record.query)' 다시 지우기" : "'\(record.query)' → '\(record.replacement)' 다시 바꾸기"
    return await run(reverted.entries.map(\.id)) { id in
      let entry = reverted.entries.first { $0.id == id }!
      return EpisodeAutosaver.Rewrite(
        changes: { text in
          let outcome = try ReplaceRevert.redoing(
            record.query, with: record.replacement, caseSensitive: record.caseSensitive,
            before: store.readSnapshot(entry.before), revertedFrom: store.readSnapshot(entry.revertedFrom), current: text)
          return (outcome.changes, outcome.kept)
        },
        beforeKind: .replace, beforeMemo: { count, _ in "\(memo) · \(count)곳" }, afterMemo: nil, date: Date(),
        actionName: "다시 바꾸기")
    } onDone: { _, _ in }
  }

  /// Run revert / redo replace per episode and count.
  private func run(
    _ ids: [EpisodeID], job: (EpisodeID) -> EpisodeAutosaver.Rewrite,
    onDone: (EpisodeID, Snapshot?) -> Void
  ) async -> RevertReport {
    var report = RevertReport()
    guard !isWorking else { return report }
    isWorking = true
    defer { isWorking = false }
    await rewriteEach(ids, job) { id, outcome in
      switch outcome {
      case .done(let count, let kept, let characters, let before):
        report.episodes += 1
        report.count += count
        report.kept += kept
        if let characters { recordCount(characters, id) }
        onDone(id, before)
      case .nothing: break
      case .conflict, .snapshotFailed, .keptChanging: report.skipped += 1
      case .unreadable: report.unreadable += 1
      }
    }
    return report
  }

  /// Replace time in the revert memo: `11월 22일 15:02`
  /// Date formatting yields `11. 22.` depending on locale, which doesn't fit the memo, so it's built by hand.
  static func stamp(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.month, .day], from: date)
    let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(time)"
  }

  /// Toast after revert / redo replace finishes
  static func summary(of report: RevertReport, redo: Bool) -> String {
    var parts: [String] = []
    if report.episodes > 0 {
      parts.append(redo ? "\(report.count.formatted())곳을 다시 바꿨어요" : "\(report.episodes)개 회차를 되돌렸어요")
    } else {
      parts.append(redo ? "다시 바꾼 곳이 없어요" : "되돌린 곳이 없어요")
    }
    if !redo, report.kept > 0 { parts.append("\(report.kept)곳은 그 뒤에 고쳐서 그대로 뒀어요") }
    if report.skipped > 0 { parts.append("\(report.skipped)개 회차는 건너뛰었어요") }
    if report.unreadable > 0 { parts.append("\(report.unreadable)개 회차는 읽지 못했어요") }
    return parts.joined(separator: " · ")
  }

  func clearFinished() {
    finished = nil
  }

  /// One line for the post-finish toast. Zero items aren't shown.
  static func summary(of report: Report) -> String {
    var parts = [report.count > 0 ? "\(report.count.formatted())곳을 바꿨어요" : "바꾼 곳이 없어요"]
    if report.skipped > 0 { parts.append("\(report.skipped)개 회차는 건너뛰었어요") }
    if report.unreadable > 0 { parts.append("\(report.unreadable)개 회차는 읽지 못했어요") }
    return parts.joined(separator: " · ")
  }
}
