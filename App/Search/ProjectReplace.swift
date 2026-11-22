import Foundation
import NovelCore
import Observation

/// 작품 전체 바꾸기(PLAN 14장). `모두 바꾸기`를 누르면 끝까지 다시 세고(`prepare`), 확인을 받으면 회차마다 바꾼다(`confirm`).
/// 검색 결과는 1,000곳에서 잘리므로 확인 창의 숫자는 검색 결과가 아니라 다시 센 것이다.
@MainActor
@Observable
final class ProjectReplace {
  /// 편집기와 창의 실행 취소 이름. 창의 ⌘Z가 이 이름이면 묻지 않고 되돌리기 창을 연다.
  static let actionName = "전체 바꾸기"
  /// 확인을 기다리는 바꾸기. 실행은 이때 센 글을 기준으로 한다.
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
        : "\(episodes)개 회차에서 \(places)곳을 '\(replacement)'(으)로 바꿀까요?"
    }

    var message: String {
      var lines = ["바꾸기 전 글은 회차마다 스냅샷으로 남겨요."]
      if !plan.unreadable.isEmpty { lines.append("읽지 못한 회차 \(plan.unreadable.count)개는 바꾸지 않아요.") }
      return lines.joined(separator: "\n")
    }

    /// 스냅샷 메모
    var memo: String {
      replacement.isEmpty ? "'\(query)' 모두 지우기" : "'\(query)' → '\(replacement)' 전체 바꾸기"
    }
  }

  /// 끝난 바꾸기의 결과
  struct Report: Equatable {
    struct Episode: Equatable {
      let id: EpisodeID
      /// 이 회차에서 바꾼 곳 수(바꾸는 순간의 글 기준)
      let count: Int
      let before: Snapshot?
    }

    var query = ""
    var replacement = ""
    /// 바꾼 회차, 바꾼 차례대로(열린 회차가 맨 끝)
    var replaced: [Episode] = []
    /// 외부 변경 충돌을 기다리는 회차
    var conflicted = 0
    /// 바꾸기 전 스냅샷을 남기지 못한 회차
    var snapshotFailed = 0
    /// 읽고 쓰는 사이에 앱 밖에서 거듭 바뀐 회차
    var keptChanging = 0
    /// 본문을 읽지 못한 회차
    var unreadable = 0

    var count: Int { replaced.reduce(0) { $0 + $1.count } }
    var skipped: Int { conflicted + snapshotFailed + keptChanging }
  }

  /// 되돌릴 수 있는 전체 바꾸기 하나(PLAN 14장 5번). 창이 열려 있는 동안만 메모리에 둔다(본문은 들지 않고 스냅샷 자리만).
  struct Record: Identifiable, Equatable {
    struct Entry: Equatable {
      let id: EpisodeID
      /// `바꾸기 전` 스냅샷. 되돌릴 때 이 글에 같은 바꾸기를 다시 해 바꾼 자리를 알아낸다.
      let before: Snapshot
    }

    let id = UUID()
    let query: String
    let replacement: String
    let caseSensitive: Bool
    let date: Date
    /// 스냅샷 메모 앞부분(`'민준' → '도윤' 전체 바꾸기`)
    let memo: String
    /// 바꾼 회차, 회차 순서대로
    let entries: [Entry]
    /// 바꾼 곳 수(되돌리기 창 머리글)
    let count: Int
  }

  /// 되돌리기 창의 한 줄: 지금 되돌리면 실제로 바뀌는 곳이 남은 회차
  struct Candidate: Identifiable, Equatable {
    let id: EpisodeID
    /// 되돌릴 곳
    let count: Int
    /// 그 뒤에 고쳐서 그대로 둘 곳
    let kept: Int
  }

  /// 되돌리기 창을 열 때 다시 감지한 것
  struct Undoable {
    let record: Record
    let candidates: [Candidate]
    /// 이미 되돌렸거나 바꾼 자리를 모두 고쳐 목록에서 뺀 회차 수
    let excluded: Int
    /// 바꾸기 전 스냅샷이나 본문을 읽지 못해 되돌릴 수 없는 회차 수(스냅샷 판에서 지웠거나 읽기 오류)
    let unreadable: Int
  }

  /// 방금 되돌린 회차들. 다시 바꾸기는 이 회차만, 되돌리기 직전 글(`되돌리기 전` 스냅샷)로 되돌린 자리를 알아낸다.
  struct Reverted {
    struct Entry {
      let id: EpisodeID
      let before: Snapshot
      let revertedFrom: Snapshot
    }

    let record: Record
    let entries: [Entry]
  }

  /// 되돌리기·다시 바꾸기의 결과
  struct RevertReport: Equatable {
    var episodes = 0
    var count = 0
    var kept = 0
    var skipped = 0
    var unreadable = 0
  }

  var replacement = ""
  private(set) var pending: Pending?
  /// 세거나 바꾸는 중. 그동안 버튼을 막는다.
  private(set) var isWorking = false
  /// 마지막으로 끝난 바꾸기. 검색 패널이 바꾼 회차 목록으로 보여 주고, 검색어를 고치거나 패널을 닫으면 비운다.
  private(set) var finished: Report?
  /// 되돌릴 수 있는 바꾸기, 오래된 것부터. 되돌리기는 최근 것부터 한다.
  private(set) var history: [Record] = []
  /// 다시 바꾸기를 기다리는 되돌리기
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

  /// 메인 스레드 밖에서 끝까지 센다. 바꿀 곳이 있으면 `pending`이 채워져 확인 창이 뜬다.
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

  /// 확인 창에서 바꾸기를 골랐다. 회차마다 지금 글에서 다시 찾아, 스냅샷을 남기고 바꾼다. 이미 바꾸는 중이면 nil.
  /// 확인 창은 버튼을 누르면 바로 닫히며 `pending`을 비우므로, 창이 보여 준 것을 받아서 실행한다.
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
    // 바꾼 회차 목록은 회차 순서대로(바꾼 차례는 열린 회차가 맨 끝이라 목록으로는 어색하다).
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

  /// 회차마다 고쳐 쓰고 끝나는 대로 알린다. 열린 회차는 맨 끝에 따로: 글을 쓰는 중이면 조합이 끝나기를 기다리는 동안
  /// 다른 회차가 먼저 끝나게. 나머지는 몇 개씩 겹쳐 돈다: 한 회차가 본문을 F_FULLFSYNC로 내리는 동안(3ms 남짓)
  /// 다음 회차의 읽기·스냅샷을 한다. 회차 안의 순서(고치기 전 스냅샷 → 본문)는 그대로이고, 본문 쓰기는 저장 줄이 하나씩 한다.
  /// 센 뒤 휴지통으로 간 회차는 알리지 않는다.
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

  /// 동시에 바꾸는 회차 수. 더 늘려도 본문 쓰기는 하나씩이라 빨라지지 않고 메모리만 쓴다.
  private static let overlap = 8

  /// 센 뒤 휴지통으로 간 회차에 쓰면 지운 본문 파일이 되살아난다. 작가가 지운 회차라 건너뜀으로 세지 않는다(nil).
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

  // MARK: - 되돌리기·다시 바꾸기 (PLAN 14장 5번)

  /// 최근 바꾸기부터, 지금 되돌리면 실제로 바뀌는 곳이 남은 것을 찾는다. 회차마다 지금 글에서 다시 감지한다
  /// (편집기 ⌘Z로 이미 되돌렸거나 바꾼 자리를 모두 고쳤으면 목록에서 빠진다). 없으면 nil.
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

  /// 한 회차의 `지금 → 되돌린 뒤` 비교(되돌리기 창 오른쪽). 메인 스레드 밖에서 만든다.
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

  /// 고른 회차만 바꾼 자리를 되돌린다. 고르지 않은 회차는 건드리지 않고 기록에 남아 다음에 창을 열면 그 회차만 보인다.
  func revert(_ record: Record, _ ids: Set<EpisodeID>) async -> RevertReport {
    // 다른 바꾸기·되돌리기가 도는 중이면 하지 않는다(그대로 두면 다시 바꾸기 기록만 지운다).
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

  /// 방금 되돌린 회차만 같은 방식으로 다시 바꾼다. `바꾸기 전` 스냅샷을 새로 남긴다.
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

  /// 되돌리기·다시 바꾸기를 회차마다 하고 센다.
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

  /// 되돌리기 메모의 바꾼 때: `11월 22일 15:02`
  /// 날짜 서식은 지역 설정에 따라 `11. 22.`처럼 나와 메모에 맞지 않아 직접 만든다.
  static func stamp(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.month, .day], from: date)
    let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(time)"
  }

  /// 되돌리기·다시 바꾸기가 끝난 뒤 토스트
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

  /// 끝난 뒤 토스트에 띄울 한 줄. 0인 항목은 띄우지 않는다.
  static func summary(of report: Report) -> String {
    var parts = [report.count > 0 ? "\(report.count.formatted())곳을 바꿨어요" : "바꾼 곳이 없어요"]
    if report.skipped > 0 { parts.append("\(report.skipped)개 회차는 건너뛰었어요") }
    if report.unreadable > 0 { parts.append("\(report.unreadable)개 회차는 읽지 못했어요") }
    return parts.joined(separator: " · ")
  }
}
