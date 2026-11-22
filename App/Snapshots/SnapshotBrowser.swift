import Foundation
import NovelCore
import Observation

/// 떠 있는 판(⇧⌘S) 하나의 상태: 한 회차의 스냅샷 목록, 고른 스냅샷, 과거↔현재 비교 (PLAN 10장 5번).
/// 목록·메모 읽기와 비교는 모두 메인 스레드 밖에서 한다. 다른 스냅샷을 고르면 하던 비교는 취소한다.
@MainActor
@Observable
final class SnapshotBrowser {
  struct Item: Identifiable, Equatable {
    let snapshot: Snapshot
    var memo: String?
    var id: String { snapshot.id }
  }

  enum Comparison: Equatable {
    case idle
    case comparing
    case ready(TextDiff)
    case failed(String)
  }

  /// 고친 줄에서 바뀐 글자가 이 비율을 넘으면 줄 전체를 칠한다. 실제 원고로 보고 사용자와 정한다(PLAN 10장 4번).
  static let wholeLineRatio = 0.5

  let episodeID: EpisodeID
  /// 판을 열 때 편집기에서 한 번 복사한 지금 본문. 판이 열려 있는 동안은 편집기에 초점이 없어 바뀌지 않는다.
  let currentText: String
  /// nil이면 아직 읽는 중
  private(set) var items: [Item]?
  private(set) var selectedID: String?
  private(set) var comparison: Comparison = .idle
  private(set) var errorMessage: String?
  /// 되돌리는 중(버튼을 두 번 누르지 않게)
  private(set) var isRestoring = false

  @ObservationIgnored private let store: ProjectStore
  @ObservationIgnored private var job: Task<TextDiff, any Error>?
  /// 처음 고를 스냅샷(바꾼 회차 목록에서 열 때 `바꾸기 전`). 없거나 못 찾으면 가장 최근 것.
  @ObservationIgnored private let preferredID: String?

  init(store: ProjectStore, episodeID: EpisodeID, currentText: String, preferredID: String? = nil) {
    self.store = store
    self.episodeID = episodeID
    self.currentText = currentText
    self.preferredID = preferredID
  }

  var selected: Item? { items?.first { $0.id == selectedID } }

  /// 목록과 메모를 읽고 처음 고를 것(없으면 가장 최근 것)을 고른다.
  func load() async {
    let store = store
    let id = episodeID
    do {
      let loaded = try await Task.detached(priority: .userInitiated) {
        try store.snapshots(of: id).reversed().map { Item(snapshot: $0, memo: store.readMemo($0)) }
      }.value
      items = loaded
      if let first = loaded.first(where: { $0.id == preferredID }) ?? loaded.first { select(first.id) }
    } catch {
      items = []
      errorMessage = "스냅샷 목록을 읽지 못했어요."
    }
  }

  func select(_ id: String) {
    guard id != selectedID, let item = items?.first(where: { $0.id == id }) else { return }
    selectedID = id
    job?.cancel()
    comparison = .comparing
    let store = store
    let current = currentText
    let ratio = Self.wholeLineRatio
    let job = Task.detached(priority: .userInitiated) {
      let old = try store.readSnapshot(item.snapshot)
      try Task.checkCancellation()
      return try TextDiff(old: old, new: current, wholeLineRatio: ratio)
    }
    self.job = job
    Task {
      let result = await job.result
      // 그사이 다른 스냅샷을 골랐으면 버린다.
      guard self.job == job else { return }
      switch result {
      case .success(let diff): comparison = .ready(diff)
      case .failure(is CancellationError): break
      case .failure: comparison = .failed("이 스냅샷을 읽지 못했어요.")
      }
    }
  }

  /// 고른 스냅샷이 지금과 달라 되돌릴 수 있는지. 비교가 끝나야 안다.
  var canRestore: Bool {
    guard !isRestoring, case .ready(let diff) = comparison else { return false }
    return diff.hasChanges
  }

  /// 고른 스냅샷으로 회차 전체를 되돌린다. 되돌렸으면 true(판을 닫는다). 실패하면 판에 이유를 띄운다.
  func restoreSelected(with autosaver: EpisodeAutosaver) async -> Bool {
    guard canRestore, let item = selected else { return false }
    isRestoring = true
    defer { isRestoring = false }
    let store = store
    let date = item.snapshot.date
    let time = SnapshotListView.time(date)
    let memo = "\(date.formatted(.dateTime.month().day())) \(time) 버전으로 되돌림"
    do {
      let text = try await Task.detached(priority: .userInitiated) { try store.readSnapshot(item.snapshot) }.value
      return try await autosaver.restore(episodeID, to: text, memo: memo, notice: "\(time) 버전으로 되돌렸어요")
    } catch EpisodeAutosaver.RestoreError.conflict {
      errorMessage = "바깥에서 바뀐 내용을 먼저 골라 주세요."
    } catch {
      errorMessage = "되돌리지 못했어요. 지금 글은 그대로예요."
    }
    return false
  }

  /// 판을 닫을 때 하던 비교를 멈춘다.
  func cancel() {
    job?.cancel()
    job = nil
  }

  /// 앞뒤 공백을 다듬어 쓰고, 비우면 메모를 없앤다. 쓰기에 성공한 뒤에 목록을 바꾼다.
  func updateMemo(_ id: String, to text: String) {
    guard let index = items?.firstIndex(where: { $0.id == id }), let item = items?[index] else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != (item.memo ?? "") else { return }
    let store = store
    Task {
      do {
        try await Task.detached { try store.writeMemo(trimmed, for: item.snapshot) }.value
        if let index = items?.firstIndex(where: { $0.id == id }) {
          items?[index].memo = trimmed.isEmpty ? nil : trimmed
        }
      } catch {
        errorMessage = "메모를 남기지 못했어요."
      }
    }
  }
}
