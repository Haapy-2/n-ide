import Foundation
import NovelCore
import Observation

/// State of one floating panel (⇧⌘S): one episode's snapshot list, the chosen snapshot, the past↔present diff (PLAN ch.10 #5).
/// Reading the list/memos and diffing all happen off the main thread. Choosing another snapshot cancels the running diff.
@MainActor
@Observable
final class SnapshotBrowser {
  struct Item: Identifiable, Equatable {
    let snapshot: Snapshot
    var memo: String?
    /// Old title of a rename snapshot. Restoring restores the title too.
    var title: String?
    /// Whether it's exempt from keep-count pruning (only rename snapshots are marked separately)
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
  /// Current body copied once from the editor when the panel opened. While the panel is open the editor has no focus, so it doesn't change.
  let currentText: String
  /// Episode title when the panel opened
  let currentTitle: String
  /// nil while still reading
  private(set) var items: [Item]?
  private(set) var selectedID: String?
  private(set) var comparison: Comparison = .idle
  private(set) var errorMessage: String?
  /// Restoring (so the button isn't pressed twice)
  private(set) var isRestoring = false
  /// A rename snapshot whose memo was edited. Ask whether to protect it.
  var askingToKeep: String?

  @ObservationIgnored private let store: ProjectStore
  @ObservationIgnored private var job: Task<TextDiff, any Error>?
  /// Snapshot to select initially (`바꾸기 전` when opened from the replaced-episodes list). Most recent if absent or not found.
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

  /// Read the list and memos, and select the initial one (most recent if none).
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
      // Discard if another snapshot was chosen meanwhile.
      guard self.job == job else { return }
      switch result {
      case .success(let diff): comparison = .ready(diff)
      case .failure(is CancellationError): break
      case .failure: comparison = .failed("이 스냅샷을 읽지 못했어요.")
      }
    }
  }

  /// Whether the chosen snapshot differs from now and can be restored (body, or a rename snapshot's title). Known only after the diff finishes.
  var canRestore: Bool {
    guard !isRestoring, case .ready(let diff) = comparison else { return false }
    return diff.hasChanges || restoredTitle != nil
  }

  /// Title that restoring would set. Only for rename snapshots differing from the current title.
  var restoredTitle: String? {
    guard let title = selected?.title, title != currentTitle else { return nil }
    return title
  }

  /// Restore the whole episode to the chosen snapshot. Body first (if that fails, the title stays too), then the title for rename snapshots.
  /// True if restored (the panel closes). On failure, show the reason in the panel.
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

  /// Stop the running diff when the panel closes.
  func cancel() {
    job?.cancel()
    job = nil
  }

  /// Trim surrounding whitespace before writing; an empty memo removes it. The list changes only after a successful write.
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
        // Rename snapshots are pruned even with a memo, so ask whether the memo edit means to keep it.
        if item.snapshot.kind == .rename, !item.isKept, !trimmed.isEmpty { askingToKeep = id }
      } catch {
        errorMessage = "메모를 남기지 못했어요."
      }
    }
  }

  /// Mark it exempt from keep-count pruning. If pruning removed it meanwhile, don't leave the mark.
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
