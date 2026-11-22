import Foundation
import NovelCore
import Observation

/// 작품 전체 바꾸기(PLAN 14장). `모두 바꾸기`를 누르면 끝까지 다시 세고(`prepare`), 확인을 받으면 회차마다 바꾼다(`confirm`).
/// 검색 결과는 1,000곳에서 잘리므로 확인 창의 숫자는 검색 결과가 아니라 다시 센 것이다.
@MainActor
@Observable
final class ProjectReplace {
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
      let after: Snapshot?
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

  var replacement = ""
  private(set) var pending: Pending?
  /// 세거나 바꾸는 중. 그동안 버튼을 막는다.
  private(set) var isWorking = false
  /// 마지막으로 끝난 바꾸기. 검색 패널이 바꾼 회차 목록으로 보여 주고, 검색어를 고치거나 패널을 닫으면 비운다.
  private(set) var finished: Report?

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
    let replacement = EpisodeAutosaver.Replacement(
      query: pending.query, replacement: pending.replacement, caseSensitive: pending.caseSensitive, date: Date(),
      memo: pending.memo)
    // 열린 회차는 맨 끝에: 글을 쓰는 중이면 조합이 끝나기를 기다리는 동안 다른 회차가 먼저 끝나게.
    let open = autosaver.episodeID
    let ids = pending.plan.episodes.map(\.id).filter { $0 != open } + pending.plan.episodes.map(\.id).filter { $0 == open }
    var report = Report(query: pending.query, replacement: pending.replacement, unreadable: pending.plan.unreadable.count)
    for id in ids {
      // 센 뒤 휴지통으로 간 회차에 쓰면 지운 본문 파일이 되살아난다. 작가가 지운 회차라 건너뜀으로 세지 않는다.
      guard episodeIDs().contains(id) else { continue }
      switch await autosaver.replace(id, replacement) {
      case .replaced(let count, let characters, let before, let after):
        report.replaced.append(.init(id: id, count: count, before: before, after: after))
        if let characters { recordCount(characters, id) }
      case .nothing: break
      case .conflict: report.conflicted += 1
      case .snapshotFailed: report.snapshotFailed += 1
      case .keptChanging: report.keptChanging += 1
      case .unreadable: report.unreadable += 1
      }
    }
    // 바꾼 회차 목록은 회차 순서대로(바꾼 차례는 열린 회차가 맨 끝이라 목록으로는 어색하다).
    let order = Dictionary(uniqueKeysWithValues: pending.plan.episodes.enumerated().map { ($1.id, $0) })
    finished = Report(
      query: report.query, replacement: report.replacement,
      replaced: report.replaced.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] },
      conflicted: report.conflicted, snapshotFailed: report.snapshotFailed, keptChanging: report.keptChanging,
      unreadable: report.unreadable)
    return report
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
