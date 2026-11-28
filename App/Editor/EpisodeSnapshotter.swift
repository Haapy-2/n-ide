import Foundation
import NovelCore

/// When snapshots are taken (PLAN ch.10 #3). Owned by the autosaver (`EpisodeAutosaver`), which hands over the body.
/// - Automatic: every configured interval, only if the current episode was edited since.
/// - Leave: episode switch, window close, quit. Always taken even with automatic off (decision 16). Not for episodes untouched this time
///   (so merely browsed episodes don't each get a snapshot).
/// - Manual (⌃⌘S): taken even without edits.
/// - Before multi-cursor: the moment ⌘D makes two cursors. So text ruined by multi-cursor can be recovered (PLAN ch.16 #4).
/// Automatic and leave skip when equal to the last snapshot, and prune by the keep count after taking.
/// Writes run off the main thread in one ordered queue (the previous must finish to check "same as last" correctly).
@MainActor
final class EpisodeSnapshotter {
  struct Settings: Equatable {
    var autoEnabled = true
    var interval: Duration = .seconds(30 * 60)
    /// How many `auto`·`leave`·`rename`·`multicursor` to keep per episode
    var retention = 50

    static let intervalChoices = [5, 10, 15, 30, 60]
    static let retentionRange = 10...100

    /// Snap Settings values (minutes, counts) to selectable values. Hand-edited UserDefaults values are filtered here too.
    init(autoEnabled: Bool = true, minutes: Int = 30, retention: Int = 50) {
      self.autoEnabled = autoEnabled
      let minutes = Self.intervalChoices.contains(minutes) ? minutes : 30
      interval = .seconds(minutes * 60)
      let clamped = min(max(retention, Self.retentionRange.lowerBound), Self.retentionRange.upperBound)
      self.retention = clamped / 10 * 10
    }
  }

  var settings = Settings() {
    didSet {
      if settings.autoEnabled != oldValue.autoEnabled || settings.interval != oldValue.interval { restartTimer() }
    }
  }

  /// At automatic snapshot time, hand over the current episode and its body. The body is fetched only if edited (to save copying).
  var currentEpisode: () -> EpisodeID? = { nil }
  var currentText: () -> String? = { nil }

  private let store: ProjectStore
  /// Episodes edited since the last snapshot
  private var edited: Set<EpisodeID> = []
  private var tail: Task<Void, Never>?
  /// Number of unfinished writes
  private var pending = 0
  /// Replace snapshots being written outside the queue. They remove themselves when done.
  private var unqueued: [UUID: Task<Void, Never>] = [:]
  private var timer: Task<Void, Never>?

  init(store: ProjectStore) {
    self.store = store
    restartTimer()
  }

  /// Whether anything remains to take (decides whether quit waits).
  var hasPendingWork: Bool { !edited.isEmpty || pending > 0 || !unqueued.isEmpty }

  func noteEdit(_ id: EpisodeID) {
    edited.insert(id)
  }

  /// On leaving an episode. If edited this time, take the body and keep it as `leave`.
  func leave(_ id: EpisodeID, text: () -> String?) {
    // If the body can't be obtained (editor already gone), keep the mark so quit shows "snapshots pending".
    guard edited.contains(id), let text = text() else { return }
    edited.remove(id)
    enqueue(text, id, .leave)
  }

  /// Manual snapshot. Waits until written and returns the snapshot.
  /// With `skipIfUnchanged`, nil without taking when equal to the last snapshot (snapshot-on-save: frequent ⌘S doesn't pile up).
  func takeManual(_ id: EpisodeID, text: String, skipIfUnchanged: Bool = false) async throws -> Snapshot? {
    edited.remove(id)
    return try await enqueue(text, id, .manual, skipIfSame: skipIfUnchanged).value
  }

  /// Right before a restore, keep the current body as `restore`. Always taken even if identical: the memo records "when and to what it was restored".
  func takeRestore(_ id: EpisodeID, text: String, memo: String) async throws -> Snapshot? {
    try await enqueue(text, id, .restore, memo: memo).value
  }

  /// Right before entering multi-cursor (`multicursor`). Skipped when equal to the last snapshot; pruned by keep count after taking.
  /// The edited-episode mark stays: text edited with multi-cursor must be kept separately at the next interval or on leave.
  func takeBeforeMultiCursor(_ id: EpisodeID, text: String) {
    enqueue(text, id, .multiCursor, skipIfSame: true)
  }

  /// On rename (`rename`). Always taken even if text is identical, together with the old title, then pruned by keep count.
  /// If `text` is nil, the file is read when its turn comes: renaming 500 episodes at once doesn't gather bodies in memory.
  /// Device cache isn't flushed: it's a record, and the F_FULLFSYNC of `project.json` saved at the same time flushes it too.
  @discardableResult
  func takeRename(_ id: EpisodeID, text: String?, title: String, memo: String, at date: Date) -> Task<Snapshot?, any Error> {
    let store = store
    let body: @Sendable () throws -> String = if let text { { text } } else { { try store.readEpisode(id) } }
    return enqueue(body, id, .rename, memo: memo, title: title, date: date, fullSync: false)
  }

  /// Bodies right before (`replace`) and after (`replaced`) replace all. Always taken and never pruned by keep count.
  /// Takes the time so snapshots from one replace share it across episodes.
  /// Device cache isn't flushed (`fullSync: false`): each episode's immediately following body write (autosave for the open one) uses F_FULLFSYNC
  /// and flushes this snapshot along with it, so "pre-replace text hits disk before the body" still holds. F_FULLFSYNC for all would be
  /// five per episode (two snapshots, two memos, the body; 3.2 ms each), several seconds for 500 episodes.
  /// Not serialized like other snapshots: no "skip if same as last" or pruning, so there's no reason to wait for earlier writes,
  /// and the queue would bottleneck replacing many episodes in parallel. At quit, `waitForWrites` waits for them too.
  func takeReplace(_ id: EpisodeID, kind: SnapshotKind, text: String, memo: String, at date: Date) async throws -> Snapshot? {
    try await startReplace(id, kind: kind, text: text, memo: memo, at: date).value
  }

  /// Same as `takeReplace` but only starts the write (post-replace snapshot: waiting would cost another main-thread round trip per episode).
  @discardableResult
  func startReplace(
    _ id: EpisodeID, kind: SnapshotKind, text: String, memo: String, at date: Date
  ) -> Task<Snapshot?, any Error> {
    let store = store
    let write = Task.detached {
      try store.writeSnapshot(text, episode: id, kind: kind, memo: memo, at: date, fullSync: false)
    }
    let key = UUID()
    unqueued[key] = Task {
      _ = await write.result
      unqueued[key] = nil
    }
    return write
  }

  /// No more snapshots for trashed episodes.
  func forget(_ id: EpisodeID) {
    edited.remove(id)
  }

  func waitForWrites() async {
    while pending > 0, let task = tail {
      await task.value
    }
    while let task = unqueued.values.first {
      await task.value
    }
  }

  /// Called every interval. Tests call it directly too.
  func autoTick() {
    guard settings.autoEnabled, let id = currentEpisode(), edited.contains(id), let text = currentText() else { return }
    edited.remove(id)
    enqueue(text, id, .auto)
  }

  private func restartTimer() {
    timer?.cancel()
    guard settings.autoEnabled else {
      timer = nil
      return
    }
    let interval = settings.interval
    timer = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled, let self else { return }
        self.autoTick()
      }
    }
  }

  @discardableResult
  private func enqueue(
    _ text: String, _ id: EpisodeID, _ kind: SnapshotKind, memo: String? = nil, skipIfSame: Bool = false
  ) -> Task<Snapshot?, any Error> {
    enqueue({ text }, id, kind, memo: memo, skipIfSame: skipIfSame)
  }

  @discardableResult
  private func enqueue(
    _ body: @escaping @Sendable () throws -> String, _ id: EpisodeID, _ kind: SnapshotKind, memo: String? = nil,
    title: String? = nil, skipIfSame: Bool = false, date: Date = Date(), fullSync: Bool = true
  ) -> Task<Snapshot?, any Error> {
    let previous = tail
    let retention = settings.retention
    let task = Task<Snapshot?, any Error> {
      await previous?.value
      defer { pending -= 1 }
      do {
        return try await write(
          body, id, kind, memo: memo, title: title, skipIfSame: skipIfSame, retention: retention, date: date,
          fullSync: fullSync)
      } catch {
        // If it failed (disk full etc.), restore the "edited" mark. If the episode is still open, it's taken again at the next interval or on leave.
        if kind.capturesEdits { edited.insert(id) }
        throw error
      }
    }
    pending += 1
    tail = Task { _ = await task.result }
    return task
  }

  private func write(
    _ body: @escaping @Sendable () throws -> String, _ id: EpisodeID, _ kind: SnapshotKind, memo: String?,
    title: String?, skipIfSame: Bool, retention: Int, date: Date, fullSync: Bool
  ) async throws -> Snapshot? {
    let store = store
    return try await Task.detached {
      let text = try body()
      // Only automatic, leave and pre-multi-cursor skip when equal to the last. Manual, pre-restore and rename record that moment, so always taken
      // (only snapshot-on-save manual snapshots skip, as an exception).
      let snapshot = try store.writeSnapshot(
        text, episode: id, kind: kind, memo: memo, title: title, at: date,
        skipIfSameAsLatest: kind.capturesEdits || skipIfSame,
        fullSync: fullSync)
      // A failed prune isn't a failure since the snapshot just taken remains. Pruning retries at the next snapshot.
      if kind.isPrunable { _ = try? store.pruneSnapshots(of: id, keeping: retention) }
      return snapshot
    }.value
  }
}
