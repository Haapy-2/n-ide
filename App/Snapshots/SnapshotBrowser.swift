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
    /// 이름 변경 스냅샷의 바뀌기 전 제목. 되돌리면 제목도 이것으로.
    var title: String?
    /// 보관 개수로 지우지 않는 것인지(이름 변경 스냅샷만 따로 표시한다)
    var isKept = false
    var id: String { snapshot.id }
  }

  enum Comparison: Equatable {
    case idle
    case comparing
    case ready(TextDiff)
    case failed(String)
  }


  let episodeID: EpisodeID
  /// 판을 열 때 편집기에서 한 번 복사한 지금 본문. 판이 열려 있는 동안은 편집기에 초점이 없어 바뀌지 않는다.
  let currentText: String
  /// 판을 열 때의 회차 제목
  let currentTitle: String
  /// nil이면 아직 읽는 중
  private(set) var items: [Item]?
  private(set) var selectedID: String?
  private(set) var comparison: Comparison = .idle
  private(set) var errorMessage: String?
  /// 되돌리는 중(버튼을 두 번 누르지 않게)
  private(set) var isRestoring = false
  /// 메모를 고친 이름 변경 스냅샷. 지킬지 묻는다.
  var askingToKeep: String?

  @ObservationIgnored private let store: ProjectStore
  @ObservationIgnored private var job: Task<TextDiff, any Error>?
  /// 처음 고를 스냅샷(바꾼 회차 목록에서 열 때 `바꾸기 전`). 없거나 못 찾으면 가장 최근 것.
  @ObservationIgnored private let preferredID: String?

  init(
    store: ProjectStore, episodeID: EpisodeID, currentText: String, currentTitle: String = "", preferredID: String? = nil
  ) {
    self.store = store
    self.episodeID = episodeID
    self.currentText = currentText
    self.currentTitle = currentTitle
    self.preferredID = preferredID
  }

  var selected: Item? { items?.first { $0.id == selectedID } }

  /// 목록과 메모를 읽고 처음 고를 것(없으면 가장 최근 것)을 고른다.
  func load() async {
    let store = store
    let id = episodeID
    do {
      let loaded = try await Task.detached(priority: .userInitiated) {
        try store.snapshots(of: id).reversed().map {
          Item(snapshot: $0, memo: store.readMemo($0), title: store.readTitle($0), isKept: store.isKept($0))
        }
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
    let job = Task.detached(priority: .userInitiated) {
      let old = try store.readSnapshot(item.snapshot)
      try Task.checkCancellation()
      return try TextDiff(old: old, new: current)
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

  /// 고른 스냅샷이 지금과 달라 되돌릴 수 있는지(본문, 또는 이름 변경 스냅샷의 제목). 비교가 끝나야 안다.
  var canRestore: Bool {
    guard !isRestoring, case .ready(let diff) = comparison else { return false }
    return diff.hasChanges || restoredTitle != nil
  }

  /// 되돌리면 바뀔 제목. 이름 변경 스냅샷이고 지금 제목과 다를 때만.
  var restoredTitle: String? {
    guard let title = selected?.title, title != currentTitle else { return nil }
    return title
  }

  /// 고른 스냅샷으로 회차 전체를 되돌린다. 본문을 먼저 되돌리고(못 하면 제목도 그대로), 이름 변경 스냅샷이면 제목도.
  /// 되돌렸으면 true(판을 닫는다). 실패하면 판에 이유를 띄운다.
  func restoreSelected(
    with autosaver: EpisodeAutosaver, renameTo rename: (String) async -> Void
  ) async -> Bool {
    guard canRestore, let item = selected, case .ready(let diff) = comparison else { return false }
    let title = restoredTitle
    isRestoring = true
    defer { isRestoring = false }
    let store = store
    let date = item.snapshot.date
    let time = SnapshotListView.time(date)
    let memo = "\(date.formatted(.dateTime.month().day())) \(time) 버전으로 되돌림"
    do {
      var restored = false
      if diff.hasChanges {
        let text = try await Task.detached(priority: .userInitiated) { try store.readSnapshot(item.snapshot) }.value
        restored = try await autosaver.restore(episodeID, to: text, memo: memo, notice: "\(time) 버전으로 되돌렸어요")
      }
      if let title {
        await rename(title)
        restored = true
      }
      return restored
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
        // 이름 변경 스냅샷은 메모가 있어도 지워지므로, 메모를 고쳐 남기려는 뜻인지 묻는다.
        if item.snapshot.kind == .rename, !item.isKept, !trimmed.isEmpty { askingToKeep = id }
      } catch {
        errorMessage = "메모를 남기지 못했어요."
      }
    }
  }

  /// 보관 개수로 지우지 않게 표시한다. 그사이 정리로 지워졌으면 표시도 남기지 않는다.
  func keep(_ id: String) {
    guard let item = items?.first(where: { $0.id == id }) else { return }
    let store = store
    Task {
      do {
        let kept = try await Task.detached { try store.keep(item.snapshot) }.value
        if kept, let index = items?.firstIndex(where: { $0.id == id }) { items?[index].isKept = true }
        if !kept { errorMessage = "이미 정리되어 지킬 수 없어요." }
      } catch {
        errorMessage = "지키기 표시를 남기지 못했어요."
      }
    }
  }
}
