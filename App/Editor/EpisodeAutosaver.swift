import AppKit
import NovelCore
import Observation

/// Episode autosave (SPEC ch.6, ch.7 #4).
/// - Saves 1 s after typing stops. Saves immediately on episode switch, window deactivation and quit (`startSave`, `flush`).
/// - `SaveQueue` performs writes in order and retries on failure.
/// - If it ultimately fails, the body is kept in memory (`unsaved`) and shown instead of the disk copy when that episode reopens.
/// - Text storage is read only, so saving during Hangul composition doesn't break it.
/// - External changes: check whether the file changed outside the app on reactivation and right before saving.
///   With no app-side changes, reload silently; if both changed, snapshot the app side and ask the user (`conflicts`).
/// - Version snapshots are taken by `snapshots`. On leave, the body already copied for saving is passed along, avoiding another copy.
@MainActor
@Observable
final class EpisodeAutosaver {
  enum Status: Equatable {
    case idle
    case saving
    /// Retrying after a failed save.
    case retrying
    case failed(Failure)
  }

  /// Save failure display. `label` is the one-line status bar text, `detail` the explanation shown on click.
  struct Failure: Equatable {
    var label = WriteProblem.other.statusLabel
    var detail = ""
    var isBackedUp = false

    init() {}

    init(_ error: Error) {
      let problem: WriteProblem =
        if case ProjectError.writeFailed(_, _, let problem) = error { problem } else { WriteProblem(error: error) }
      label = problem.statusLabel
      detail = (error as? ProjectError)?.userMessage ?? error.localizedDescription
    }
  }

  /// An episode that collided with an external change. It isn't saved until the user chooses.
  struct Conflict: Equatable {
    let episodeID: EpisodeID
    /// Current disk state (content changed outside the app).
    let disk: DiskVersion
    /// Change number when `snapshot` was taken. If edited after that, some text isn't in the snapshot.
    var change: Int
    /// Snapshot holding the app-side body. nil while it's being written.
    var snapshot: URL?
    /// Whether the snapshot write finished (including failure). We ask only after it finishes.
    var isReady = false
    /// The side to discard, if switching to the chosen side stopped because it couldn't be snapshotted. The dialog shows why.
    var unkept: Side?

    enum Side: Equatable {
      /// Text written in this app
      case app
      /// Text changed outside the app
      case disk
    }
  }

  private(set) var status: Status = .idle
  private(set) var conflicts: [EpisodeID: Conflict] = [:]
  /// On only when a save takes over 0.5 s. Normal saves show nothing on screen (DESIGN.md ch.4).
  private(set) var showsSavingIndicator = false
  /// Notice shown in the status bar right after a restore (`14:23:05 버전으로 되돌렸어요`). Disappears on the next input or episode switch.
  private(set) var restoreNotice: String?

  let store: ProjectStore
  let snapshots: EpisodeSnapshotter
  private let queue: SaveQueue
  private let delay: Duration
  private let maxWait: Duration
  @ObservationIgnored private weak var textView: ManuscriptTextView?
  @ObservationIgnored private(set) var episodeID: EpisodeID?
  /// The snapshot panel is open (`beginPanel`…`endPanel`). External-change checks are deferred meanwhile.
  @ObservationIgnored private var isHoldingExternalChanges = false
  /// Per-episode change number. Increases by 1 on every edit.
  @ObservationIgnored private var changes: [EpisodeID: Int] = [:]
  @ObservationIgnored private var savedChanges: [EpisodeID: Int] = [:]
  /// Body of an episode whose save failed. Carries its change number to tell which is newer than the one being written.
  @ObservationIgnored private var unsaved: [EpisodeID: SaveJob] = [:]
  /// Body of the episode currently being written to file.
  @ObservationIgnored private var inFlight: [EpisodeID: SaveJob] = [:]
  @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  /// Time of the first change in the current episode not yet being saved.
  @ObservationIgnored private var waitingSince: ContinuousClock.Instant?
  /// Description of the last save failure. Shown in the status bar while the failed manuscript remains.
  @ObservationIgnored private var lastFailure = Failure()
  @ObservationIgnored let disk = DiskVersions()

  init(
    store: ProjectStore, queue: SaveQueue = SaveQueue(), delay: Duration = .seconds(1), maxWait: Duration = .seconds(10)
  ) {
    self.store = store
    self.queue = queue
    self.delay = delay
    self.maxWait = maxWait
    snapshots = EpisodeSnapshotter(store: store)
    AutosaverRegistry.shared.register(self)
    snapshots.currentEpisode = { [weak self] in self?.episodeID }
    snapshots.currentText = { [weak self] in self?.textView?.string }
  }

  /// Whether there's work to finish before quitting: unsaved changes, pending leave snapshots, snapshots being written.
  var hasWorkBeforeQuit: Bool {
    hasUnsavedChanges || snapshots.hasPendingWork || hasProjectWork() || bulkRewrites > 0
  }

  /// Multi-episode rewrites in progress (replace all / revert / redo replace). Between episodes no save is in flight,
  /// so wait until they finish to avoid quit or window close ending with only some episodes changed.
  @ObservationIgnored private var bulkRewrites = 0
  /// When the editor text last changed. Used to wait for typing to pause before rewriting the open episode.
  @ObservationIgnored private var lastInput: ContinuousClock.Instant?
  /// When the 2-set IME (macOS 27) continues composing without displayed characters, `hasMarkedText` is false, so composition can't be detected.
  /// Editing in that gap makes the IME drop the character in progress (`forgetInputInProgress`), splitting it (가 + ㄱ → "가ㄱ"),
  /// so edit only after input pauses this long.
  static let inputPause: Duration = .milliseconds(500)

  func beginBulkRewrite() { bulkRewrites += 1 }
  func endBulkRewrite() { bulkRewrites -= 1 }

  /// Whether the project side (`project.json`: episode list, deferred counts) has saves to finish, and how to finish them. Set by `ProjectModel`.
  /// App quit only looks at the autosaver list, so it's hooked here to be awaited too.
  @ObservationIgnored var hasProjectWork: () -> Bool = { false }
  @ObservationIgnored var finishProjectWork: () async -> Void = {}

  /// Whether there are unsaved changes (current episode, failed episodes, or unresolved external-change conflicts).
  var hasUnsavedChanges: Bool {
    if let episodeID, isDirty(episodeID) { return true }
    return !unsaved.isEmpty || !running.isEmpty
  }

  /// Whether any unsaved change is preserved nowhere. Only these get retry/export.
  /// A conflict episode's app-side text counts as preserved if it's intact in the `conflict` snapshot (re-saving can't resolve the conflict).
  var hasUnprotectedChanges: Bool {
    if let episodeID, isDirty(episodeID), !isKeptInSnapshot(episodeID) { return true }
    return unsaved.keys.contains { !isKeptInSnapshot($0) } || !running.isEmpty
  }

  /// Number of unresolved conflict episodes whose app-side text is intact in a snapshot. Reported separately at quit.
  var conflictsKeptInSnapshots: Int { conflicts.keys.filter(isKeptInSnapshot).count }

  /// Whether every unpreserved manuscript was actually written to the out-of-project backup (quit warning, status bar text). Conflict episodes aren't backed up.
  var unprotectedAreBackedUp: Bool {
    backup != nil && unsaved.keys.allSatisfy { isKeptInSnapshot($0) || (conflicts[$0] == nil && isBackedUp($0)) }
  }

  /// Whether that episode's latest text was written to the backup. Not if edited after the write.
  private func isBackedUp(_ id: EpisodeID) -> Bool {
    guard let written = writtenBackups[id] else { return false }
    return written >= changes[id, default: 0]
  }

  private func isKeptInSnapshot(_ id: EpisodeID) -> Bool {
    guard let conflict = conflicts[id], conflict.snapshot != nil else { return false }
    return changes[id, default: 0] == conflict.change
  }

  /// Episode title, used as the file name when exporting an unsaved manuscript elsewhere. Set by `ProjectModel`.
  @ObservationIgnored var episodeTitle: (EpisodeID) -> String = { _ in "" }
  /// Whether the episode is in the list now. A late write to a trashed episode would resurrect its deleted body file, so replace all checks right before writing.
  @ObservationIgnored var isListed: (EpisodeID) -> Bool = { _ in true }
  @ObservationIgnored var projectTitle: () -> String = { "" }

  /// Where manuscripts that ultimately failed to save are kept outside the project. Absent (test default) = no backup.
  @ObservationIgnored var backup: EmergencyBackup?
  /// Episodes backed up this run and their change numbers. The backup is deleted once a newer body is saved.
  @ObservationIgnored private var backedUp: [EpisodeID: Int] = [:]
  /// Of those, the ones actually written to the backup file. A failed write (disk full etc.) isn't included, so we never claim "backed up".
  @ObservationIgnored private var writtenBackups: [EpisodeID: Int] = [:]
  /// Backup writes/deletes in order (so an old write finishing after a new delete doesn't leave a stale backup).
  @ObservationIgnored private var backupTail: Task<Void, Never>?

  /// Manuscripts that ultimately couldn't be saved and live only in memory (to export elsewhere on window close or quit).
  /// Excludes episodes intact in a conflict snapshot (no need to export).
  func unsavedManuscripts() -> [(title: String, text: String)] {
    unsaved.values.filter { !isKeptInSnapshot($0.id) }.sorted { $0.id.rawValue < $1.id.rawValue }
      .map { (episodeTitle($0.id), $0.text) }
  }

  /// Manuscripts not yet confirmed written to disk: failed, being written, or unsaved text in the open episode.
  /// Used when the user exports instead of waiting for a slow quit.
  func pendingManuscripts() -> [(title: String, text: String)] {
    var texts: [EpisodeID: String] = [:]
    for id in Set(unsaved.keys).union(inFlight.keys) { texts[id] = pendingText(for: id) }
    if let episodeID, isDirty(episodeID), let textView { texts[episodeID] = textView.string }
    return texts.sorted { $0.key.rawValue < $1.key.rawValue }.map { (episodeTitle($0.key), $0.value) }
  }

  /// The user exported elsewhere. Release the in-memory manuscripts so they no longer count as "unsaved".
  /// Episodes kept in conflict snapshots weren't exported, so leave them (the app-side text is needed when resolving later).
  func markRescued() {
    for id in unsaved.keys where !isKeptInSnapshot(id) {
      savedChanges[id] = max(savedChanges[id, default: 0], changes[id, default: 0])
      unsaved[id] = nil
    }
    if case .failed = status { settleStatus() }
  }

  func attach(_ textView: ManuscriptTextView) {
    self.textView = textView
    // The body is copied once on main on entry; the snapshot queue writes off main.
    textView.onEnterMultiCursor = { [weak self, weak textView] in
      guard let self, let textView, let id = episodeID else { return }
      snapshots.takeBeforeMultiCursor(id, text: textView.string)
    }
  }

  /// Body to show instead of disk when opening an episode: kept in memory after a failed save, or still being written. nil if none.
  /// (So quickly going A→B→A doesn't read A's old disk body before its save finishes.)
  /// If both exist (wrote more after a failure, left, and the new save is still in flight), the larger change number is newer.
  /// Showing the old failed body would let continued typing overwrite what was written in between.
  func pendingText(for id: EpisodeID) -> String? {
    guard let failed = unsaved[id] else { return inFlight[id]?.text }
    guard let writing = inFlight[id], writing.change > failed.change else { return failed.text }
    return writing.text
  }

  /// Text project search uses instead of files: unsaved or in-flight text, and for the open episode the editor's current text.
  /// The disk file may be a second old, so just-typed text is still found.
  func searchTexts() -> [EpisodeID: String] {
    var texts: [EpisodeID: String] = [:]
    for id in Set(unsaved.keys).union(inFlight.keys) { texts[id] = pendingText(for: id) }
    if let episodeID, let textView { texts[episodeID] = textView.string }
    return texts
  }

  /// Called after a new episode is loaded into the editor. If read from disk, pass that state (`version`).
  /// (nil when opened from an in-memory body: keep the previously remembered baseline.)
  func begin(episode id: EpisodeID, version: DiskVersion? = nil) {
    episodeID = id
    waitingSince = nil
    if let version { disk[id] = version }
    // When opened from an in-memory body, retry saving right away.
    if unsaved[id] != nil { scheduleSave() }
  }

  /// On leaving an episode. Copy the current body now and start saving, without waiting.
  /// Waiting for the save before showing the next episode would make switching look choppy.
  func leaveEpisode() {
    restoreNotice = nil
    snapshotLeaving()
    let left = episodeID
    episodeID = nil
    if let left { releaseBaselineIfIdle(left) }
  }

  /// Release the left episode's disk baseline. It holds the whole body, so keeping it would pile up memory for every browsed episode.
  /// Only released when nothing is pending or in flight. Reopening reads disk afresh for a new baseline.
  private func releaseBaselineIfIdle(_ id: EpisodeID) {
    guard id != episodeID, !isDirty(id), inFlight[id] == nil, conflicts[id] == nil else { return }
    disk[id] = nil
  }

  /// Whether the episode holds a disk baseline (for tests).
  func holdsBaseline(for id: EpisodeID) -> Bool { disk[id] != nil }

  /// Called in place when a window closes: does only the first part of `finish` (leave snapshot, start save) without waiting.
  /// After window close handling the editor (weak reference) may vanish first, so the body is copied before that.
  func startFinishing() {
    snapshotLeaving()
  }

  /// On window close or quit: take the leave snapshot and wait until saving and snapshot writes all finish.
  func finish() async {
    while bulkRewrites > 0 { try? await Task.sleep(for: .milliseconds(20)) }
    snapshotLeaving()
    await flush()
    await backupTail?.value
    await snapshots.waitForWrites()
    // If the save just above produced an external-change conflict, wait for the app-side text to be fully snapshotted.
    // Whether it was kept decides the quit warning (preserved conflict / manuscript to export).
    while conflicts.values.contains(where: { !$0.isReady }) { try? await Task.sleep(for: .milliseconds(20)) }
    await finishProjectWork()
  }

  /// Start saving, and if this episode was edited, take a `leave` snapshot with the same body.
  private func snapshotLeaving() {
    pendingSave?.cancel()
    pendingSave = nil
    let job = makeSaveJob()
    if let job { start(job) }
    if let id = episodeID { snapshots.leave(id) { job?.text ?? textView?.string } }
  }

  /// Manual snapshot (⌃⌘S): finish saving first, then snapshot the current body. nil if no episode is open.
  /// With `skipIfUnchanged`, also nil when equal to the last snapshot (snapshot-on-save).
  func takeManualSnapshot(skipIfUnchanged: Bool = false) async throws -> Snapshot? {
    guard let id = episodeID else { return nil }
    await flush()
    guard id == episodeID, let text = textView?.string else { return nil }
    return try await snapshots.takeManual(id, text: text, skipIfUnchanged: skipIfUnchanged)
  }

  /// `rename` snapshot of renamed episodes. The open episode uses the editor text, unsaved or in-flight episodes that text,
  /// others read the file when their turn comes (the disk text is that episode's current text).
  func snapshotRename(_ id: EpisodeID, title: String, memo: String, at date: Date) -> Task<Snapshot?, any Error> {
    let text = id == episodeID ? textView?.string ?? pendingText(for: id) : pendingText(for: id)
    return snapshots.takeRename(id, text: text, title: title, memo: memo, at: date)
  }

  /// Opening the floating panel (⇧⌘S): end editor composition, release focus, then copy the current body once.
  /// nil without an editor. `hadFocus` is passed back to `endPanel` on close.
  /// While the panel is open, external changes aren't loaded: the panel's "current" is the body copied here, so the diff would go wrong.
  func beginPanel() -> (text: String, hadFocus: Bool)? {
    guard let textView else { return nil }
    let hadFocus = yieldFocus()
    isHoldingExternalChanges = true
    return (textView.string, hadFocus)
  }

  /// On panel close. Run the external-change check deferred while it was open, once.
  func endPanel(hadFocus: Bool) {
    isHoldingExternalChanges = false
    if hadFocus { regainFocus() }
    Task { await checkExternalChange() }
  }

  /// End editor composition and release keyboard focus. Returns whether the editor had focus.
  func yieldFocus() -> Bool {
    textView?.yieldFocusForPanel() ?? false
  }

  func regainFocus() {
    textView?.regainFocusAfterPanel()
  }

  /// Called after an episode is trashed. Discards remaining save state for that episode.
  /// (Prevents a later save from resurrecting a deleted episode's file. Finish saving with `flush` before calling.)
  func forget(episode id: EpisodeID) {
    if episodeID == id {
      pendingSave?.cancel()
      pendingSave = nil
      episodeID = nil
    }
    // Change numbers are never reset to 0. The save queue remembers the last number written for this episode, so
    // after restoring from trash with ⌘Z, counting from 1 again would make new saves look "old" and be silently skipped.
    if let change = changes[id] { savedChanges[id] = change }
    unsaved[id] = nil
    inFlight[id] = nil
    conflicts[id] = nil
    disk[id] = nil
    removeBackup(id)
    snapshots.forget(id)
    if case .failed = status { settleStatus() }
  }

  func textDidChange() {
    restoreNotice = nil
    lastInput = .now
    guard let episodeID else { return }
    noteChange(episodeID)
  }

  private func noteChange(_ id: EpisodeID) {
    changes[id, default: 0] += 1
    snapshots.noteEdit(id)
    scheduleSave()
  }

  // MARK: - Restore from snapshot (PLAN ch.10 #6)

  enum RestoreError: Error {
    case notOpen
    /// The external-change conflict isn't resolved yet.
    case conflict
    /// The episode or body changed while the pre-restore snapshot was being taken.
    case changedMeanwhile
  }

  /// First keep the current body as a `restore` snapshot (with memo); only after that replace the editor body.
  /// If it can't be kept, throw and leave the body as is. Saving afterwards is left to normal autosave (the body file isn't overwritten directly).
  /// False if identical to now and nothing to change.
  func restore(_ id: EpisodeID, to text: String, memo: String, notice: String) async throws -> Bool {
    guard id == episodeID, let textView else { throw RestoreError.notOpen }
    guard conflicts[id] == nil else { throw RestoreError.conflict }
    let current = textView.string
    guard current != text else { return false }
    _ = try await snapshots.takeRestore(id, text: current, memo: memo)
    // If it changed while waiting, don't touch it. Keep the snapshot taken (nothing gained by deleting it).
    guard id == episodeID, conflicts[id] == nil, self.textView === textView, !textView.hasMarkedText(),
      textView.string == current
    else { throw RestoreError.changedMeanwhile }
    guard textView.replaceAllUndoably(with: text, actionName: "스냅샷으로 되돌리기") else { return false }
    // The editor notification also arrives (counting twice is harmless), but count directly so it saves even without a notification.
    noteChange(id)
    restoreNotice = notice
    return true
  }

  /// Status bar "Cancel": back to just before the restore. While the notice shows nothing was edited since, so the top undo is the restore.
  func undoRestore() {
    guard restoreNotice != nil, let textView, let id = episodeID else { return }
    restoreNotice = nil
    textView.undo(nil)
    noteChange(id)
    textView.regainFocusAfterPanel()
  }

  // MARK: - Replace all / revert / redo replace (PLAN ch.14 #2·5)

  /// Rewriting one episode. Replace all, reverting only replaced spots, and redo replace all take the same path:
  /// edit only after snapshotting the current text; the open episode is edited in the editor at just the target spots after composition ends,
  /// others are written conditionally via the save queue, rereading on mismatch up to 3 times.
  struct Rewrite: Sendable {
    /// Spots to edit in the current text, and how many were left alone (in revert, spots edited since). Called off the main thread.
    /// If it throws (snapshot unreadable etc.), the episode counts as unreadable.
    let changes: @Sendable (String) throws -> (changes: [TextChange], kept: Int)
    let beforeKind: SnapshotKind
    /// Pre-edit snapshot memo. Receives the edit count and the left-alone count.
    let beforeMemo: @Sendable (_ count: Int, _ kept: Int) -> String
    /// Post-edit snapshot memo. nil = don't keep one (only replace all keeps `바꾼 뒤`).
    let afterMemo: (@Sendable (_ count: Int) -> String)?
    /// Snapshot time. All episodes in one operation share it so they can be recognized as one.
    let date: Date
    /// Editor undo action name
    let actionName: String

    /// Replace all. `· 바꾸기 전 · 12곳` is appended after `memo`.
    static func replace(query: String, replacement: String, caseSensitive: Bool, date: Date, memo: String) -> Self {
      Self(
        changes: { text in
          (TextReplace.ranges(of: query, in: text, caseSensitive: caseSensitive).map {
            TextChange(range: $0, text: replacement)
          }, 0)
        },
        beforeKind: .replace, beforeMemo: { count, _ in "\(memo) · 바꾸기 전 · \(count)곳" },
        afterMemo: { "\(memo) · 바꾼 뒤 · \($0)곳" }, date: date, actionName: ProjectReplace.actionName)
    }
  }

  enum RewriteOutcome: Equatable {
    /// Edited. If an unopened episode ultimately couldn't be written, it's held in memory like a normal save failure and the status bar reports it.
    /// `characters` is the edited text's count. nil for the open episode, whose counting the editor handles.
    /// The `바꾼 뒤` snapshot is only started here, so it's not included (find it by the same time and kind `replaced`).
    case done(count: Int, kept: Int, characters: CharacterCount?, before: Snapshot?)
    /// Nothing to edit in the current text.
    case nothing
    /// The external-change conflict isn't resolved yet.
    case conflict
    /// Couldn't take the pre-edit snapshot.
    case snapshotFailed
    /// Couldn't read the body (or the snapshot used for revert).
    case unreadable
    /// Changed outside the app repeatedly between read and write.
    case keptChanging
  }

  /// Whether this undo record belongs to the open episode's editor (to tell if editor ⌘Z undid a replace all).
  func ownsEditorUndo(_ manager: UndoManager) -> Bool {
    textView?.undoManager === manager
  }

  /// Edit one episode. Target spots are recomputed from the text at edit time, not when counted (edits made meanwhile aren't skipped).
  func rewrite(_ id: EpisodeID, _ job: Rewrite) async -> RewriteOutcome {
    var before: (text: String, snapshot: Snapshot?)?
    for _ in 0..<3 {
      if let outcome = await rewriteAttempt(id, job, before: &before) { return outcome }
    }
    return .keptChanging
  }

  /// One attempt. nil if state changed meanwhile and it must be retried.
  private func rewriteAttempt(
    _ id: EpisodeID, _ job: Rewrite, before: inout (text: String, snapshot: Snapshot?)?
  ) async -> RewriteOutcome? {
    if id == episodeID, textView != nil { return await rewriteOpen(id, job, before: &before) }
    // If a save is in flight, wait for it. Editing the text after that save is what keeps the order right.
    while id != episodeID, inFlight[id] != nil, let task = running.values.first {
      await task.value
    }
    if id == episodeID { return nil }
    if conflicts[id] != nil { return .conflict }
    let pending = pendingText(for: id)
    let store = store
    let source: (text: String, version: DiskVersion?)
    if let pending {
      source = (pending, nil)
    } else {
      guard let read = try? await Task.detached(operation: { try store.readEpisodeVersion(id) }).value else {
        return .unreadable
      }
      source = (read.text, read)
    }
    let (changes, text) = (job.changes, source.text)
    let computed: (text: String, count: Int, kept: Int, characters: CharacterCount)?
    do {
      computed = try await Task.detached {
        let found = try changes(text)
        guard !found.changes.isEmpty else { return nil }
        let result = TextChange.applying(found.changes, to: text)
        return (result, found.changes.count, found.kept, CharacterCount(counting: result))
      }.value
    } catch {
      return .unreadable
    }
    guard let computed else { return .nothing }
    let beforeSnapshot: Snapshot?
    do {
      beforeSnapshot = try await snapshotBefore(id, source.text, count: computed.count, kept: computed.kept, job, &before)
    } catch {
      return .snapshotFailed
    }
    // If it got opened, a conflict arose, or the in-memory text changed while waiting, start over.
    guard id != episodeID, conflicts[id] == nil, inFlight[id] == nil, pendingText(for: id) == pending else { return nil }
    // If it was trashed while the snapshot was being written, don't write. The write starts right here (`running`), and a later trash
    // waits for the save and moves the edited body along.
    guard isListed(id) else { return .nothing }
    guard await writeReplacement(id, text: computed.text, readVersion: source.version) else { return nil }
    if let afterMemo = job.afterMemo {
      snapshots.startReplace(id, kind: .replaced, text: computed.text, memo: afterMemo(computed.count), at: job.date)
    }
    return .done(count: computed.count, kept: computed.kept, characters: computed.characters, before: beforeSnapshot)
  }

  /// Open episode: once Hangul composition and typing pause, decide spots in the current text and snapshot it, then edit only those spots
  /// while the editor text is still that text. If it changes during deciding/snapshotting (await), redecide and resnapshot with the new text.
  /// So `바꾸기 전` is always exactly the text that was edited. A search term typed meanwhile changes too, and if it's missing from the snapshot
  /// revert can't find that spot. There's no await between the final comparison and the edit, so input can't slip in.
  private func rewriteOpen(
    _ id: EpisodeID, _ job: Rewrite, before: inout (text: String, snapshot: Snapshot?)?
  ) async -> RewriteOutcome? {
    var basis: String?
    var found: (changes: [TextChange], kept: Int) = ([], 0)
    var beforeSnapshot: Snapshot?
    while true {
      guard id == episodeID, let textView else { return nil }
      if conflicts[id] != nil { return .conflict }
      if textView.hasMarkedText() || lastInput.map({ ContinuousClock.now - $0 < Self.inputPause }) == true {
        try? await Task.sleep(for: .milliseconds(50))
        continue
      }
      let current = textView.string
      // Compare literally (String == treats decomposed jamo as equal, which can misalign UTF-16 positions).
      guard let basis, current.utf16.elementsEqual(basis.utf16) else {
        basis = current
        guard let again = await Self.changes(job, in: current) else { return .unreadable }
        guard !again.changes.isEmpty else { return .nothing }
        found = again
        do {
          beforeSnapshot = try await snapshotBefore(id, current, count: found.changes.count, kept: found.kept, job, &before)
        } catch {
          return .snapshotFailed
        }
        continue
      }
      guard textView.replaceOccurrences(found.changes, actionName: job.actionName) else {
        return .nothing
      }
      noteChange(id)
      if let afterMemo = job.afterMemo {
        snapshots.startReplace(
          id, kind: .replaced, text: textView.string, memo: afterMemo(found.changes.count), at: job.date)
      }
      return .done(count: found.changes.count, kept: found.kept, characters: nil, before: beforeSnapshot)
    }
  }

  private static func changes(_ job: Rewrite, in text: String) async -> (changes: [TextChange], kept: Int)? {
    let changes = job.changes
    return try? await Task.detached { try changes(text) }.value
  }

  /// Pre-edit snapshot. Not taken again on retry if the text is the same.
  private func snapshotBefore(
    _ id: EpisodeID, _ text: String, count: Int, kept: Int, _ job: Rewrite,
    _ before: inout (text: String, snapshot: Snapshot?)?
  ) async throws -> Snapshot? {
    if let before, before.text.utf16.elementsEqual(text.utf16) { return before.snapshot }
    let snapshot = try await snapshots.takeReplace(
      id, kind: job.beforeKind, text: text, memo: job.beforeMemo(count, kept), at: job.date)
    before = (text, snapshot)
    return snapshot
  }

  /// Write the edited text via the save queue. Conditional on the read state if from file, or against the disk baseline if from memory.
  /// False if not written because it changed outside the app meanwhile (reread and replace).
  private func writeReplacement(_ id: EpisodeID, text: String, readVersion: DiskVersion?) async -> Bool {
    changes[id, default: 0] += 1
    let job = SaveJob(id: id, change: changes[id, default: 0], text: text)
    inFlight[id] = job
    let key = UUID()
    let write = Task { await commitReplacement(job, readVersion: readVersion) }
    running[key] = Task {
      _ = await write.value
      running[key] = nil
    }
    return await write.value
  }

  private func commitReplacement(_ job: SaveJob, readVersion: DiskVersion?) async -> Bool {
    let store = store
    let disk = disk
    defer {
      if inFlight[job.id]?.text == job.text { inFlight[job.id] = nil }
      releaseBaselineIfIdle(job.id)
    }
    do {
      let result = try await queue.save(.episode(job.id), change: job.change, writeReturning: {
        let result = try store.writeEpisode(job.text, id: job.id, ifUnchangedSince: readVersion ?? disk[job.id])
        if case .written(let version) = result { disk[job.id] = version }
        return result
      }, didWrite: { if case .written = $0 { true } else { false } })
      guard case .written = result else {
        // Discard the edited text. This number must count as saved, or an untouched episode would stay "unsaved".
        savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
        return false
      }
      savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
      if let failed = unsaved[job.id], failed.change <= job.change { unsaved[job.id] = nil }
      if let backed = backedUp[job.id], backed <= job.change { removeBackup(job.id) }
      settleStatus()
    } catch {
      // Keep the baseline so the next save attempt also compares against the file as read.
      if disk[job.id] == nil, let readVersion { disk[job.id] = readVersion }
      if (unsaved[job.id]?.change ?? 0) <= job.change {
        unsaved[job.id] = job
        backUp(job)
        lastFailure = Failure(error)
      }
      settleStatus()
    }
    return true
  }

  /// Copy the current body in place and only start saving (window deactivation). Doesn't wait for completion.
  /// Called inside a `Task`, it would run only after window-close handling, and if the editor (weak reference) vanished meanwhile the body couldn't be read.
  func startSave() {
    pendingSave?.cancel()
    pendingSave = nil
    if let job = makeSaveJob() { start(job) }
  }

  /// Save now and wait until every save, including those already started, finishes (⌘S, window close, quit).
  /// Also re-save other episodes left in memory after failed saves. Saving only the open one would lose them when the window closes.
  func flush() async {
    startSave()
    for job in unsaved.values where job.id != episodeID && inFlight[job.id] == nil && conflicts[job.id] == nil {
      start(job)
    }
    while let task = running.values.first {
      await task.value
    }
  }

  // MARK: - External changes

  /// On window reactivation, check in the background whether the current episode file changed outside the app.
  func checkExternalChange() async {
    guard !isHoldingExternalChanges, let id = episodeID, conflicts[id] == nil, let known = disk[id] else { return }
    let store = store
    let disk = disk
    let result = await Task.detached { () -> DiskCheck? in
      guard let result = try? store.checkEpisode(id, against: known) else { return nil }
      if case .unchanged(let refreshed) = result {
        if refreshed != known { _ = disk.replace(id, ifStill: known, with: refreshed) }
        return result
      }
      // If the app saved and moved the baseline during the check, the change just seen may be the app's own save, so drop it.
      // (A real external change would be caught first by that save's pre-write check.)
      return disk[id] == known ? result : nil
    }.value
    // Don't touch anything if the episode changed or a finished save moved the baseline while waiting.
    guard let result, !isHoldingExternalChanges, episodeID == id, conflicts[id] == nil, disk[id] == known else { return }
    switch result {
    case .unchanged:
      break
    case .missing:
      // The body file was deleted outside the app. Rewrite it from the body the app holds to protect the manuscript.
      changes[id, default: 0] += 1
      scheduleSave()
    case .changed(let diskVersion):
      if hasAppChanges(id) {
        raiseConflict(id, disk: diskVersion, appText: textView?.string ?? "")
      } else {
        // No app-side changes, so switch to the external content without asking. No await between decision and swap, so input can't slip in.
        disk[id] = diskVersion
        textView?.reloadText(with: diskVersion.text)
      }
    }
  }

  /// Whether the app holds content not yet on disk: unsaved input, an in-flight save, or composing characters.
  /// Multi-cursor too (PLAN ch.16 X4): a reload would silently drop the selected spots.
  private func hasAppChanges(_ id: EpisodeID) -> Bool {
    isDirty(id) || inFlight[id] != nil || (textView?.hasMarkedText() ?? false) || textView?.multiCursor != nil
  }

  /// Both changed. Hold the app-side body in memory, snapshot it, and ask once fully kept (`conflicts`).
  private func raiseConflict(_ id: EpisodeID, disk diskVersion: DiskVersion, appText: String) {
    guard conflicts[id] == nil else { return }
    // For the episode being viewed, the on-screen body is newer than the copy made for the save task.
    let text = (id == episodeID ? textView?.string : nil) ?? appText
    unsaved[id] = SaveJob(id: id, change: changes[id, default: 0], text: text)
    conflicts[id] = Conflict(episodeID: id, disk: diskVersion, change: changes[id, default: 0])
    let store = store
    Task {
      let snapshot = try? await Task.detached { try store.writeSnapshot(text, episode: id, kind: .conflict)?.url }.value
      conflicts[id]?.snapshot = snapshot
      conflicts[id]?.isReady = true
    }
  }

  /// The user chose "this app's content". Snapshot the external content being overwritten too, then save the app-side body.
  /// If it can't be kept, don't overwrite; leave the conflict (only the snapshot folder may be blocked while body saving works).
  func keepAppVersion(_ id: EpisodeID) async {
    guard let conflict = conflicts[id], conflict.isReady else { return }
    let store = store
    do {
      _ = try await Task.detached {
        try store.writeSnapshot(conflict.disk.text, episode: id, kind: .external)
      }.value
    } catch {
      conflicts[id]?.unkept = .disk
      return
    }
    guard conflicts.removeValue(forKey: id) != nil else { return }
    // Update the baseline to mean "overwriting with knowledge of the current disk state". If it changes again, the pre-save check asks again.
    disk[id] = conflict.disk
    changes[id, default: 0] += 1
    let text = id == episodeID ? textView?.string : unsaved[id]?.text
    if let text {
      pendingSave?.cancel()
      pendingSave = nil
      start(SaveJob(id: id, change: changes[id, default: 0], text: text))
    }
  }

  /// The user chose "the externally changed content". Before discarding, make sure the app's current text is intact in a snapshot:
  /// if the conflict snapshot failed or more was written since, take one now. If that fails, don't discard; leave the conflict.
  /// It may have changed again while choosing, so reread now. Read directly like an episode switch (~5,000 chars, ~0.1 ms):
  /// so characters typed while waiting aren't immediately overwritten and lost.
  func useDiskVersion(_ id: EpisodeID) async {
    while conflicts[id] != nil, !isKeptInSnapshot(id) {
      guard let text = (id == episodeID ? textView?.string : nil) ?? unsaved[id]?.text else { break }
      let change = changes[id, default: 0]
      let store = store
      do {
        let url = try await Task.detached { try store.writeSnapshot(text, episode: id, kind: .conflict)?.url }.value
        conflicts[id]?.snapshot = url
        conflicts[id]?.change = change
      } catch {
        conflicts[id]?.unkept = .app
        return
      }
    }
    guard let conflict = conflicts.removeValue(forKey: id) else { return }
    let version = (try? store.readEpisodeVersion(id)) ?? conflict.disk
    disk[id] = version
    unsaved[id] = nil
    inFlight[id] = nil
    removeBackup(id)
    savedChanges[id] = changes[id, default: 0]
    if id == episodeID { textView?.reloadText(with: version.text) }
    if case .failed = status { settleStatus() }
  }

  /// When one save finishes, sync the status bar to the actual state. Overwriting with the last save's result would, after another episode saves,
  /// clear the earlier episode's failure and leave "saving" stuck. Conflicts don't show as failures.
  private func settleStatus() {
    guard unsaved.keys.contains(where: { conflicts[$0] == nil }) else {
      status = .idle
      return
    }
    var failure = lastFailure
    failure.isBackedUp = unprotectedAreBackedUp
    status = .failed(failure)
  }

  /// Save once input pauses for `delay`. Continuous typing would postpone this wait forever, so
  /// once `maxWait` has passed since the first unsaved change, don't wait for a pause.
  private func scheduleSave() {
    pendingSave?.cancel()
    let now = ContinuousClock.now
    let since = waitingSince ?? now
    waitingSince = since
    let wait = min(delay, max(.zero, since + maxWait - now))
    pendingSave = Task { [wait] in
      if wait > .zero { try? await Task.sleep(for: wait) }
      guard !Task.isCancelled else { return }
      if let job = self.makeSaveJob() { self.start(job) }
    }
  }

  private func isDirty(_ id: EpisodeID) -> Bool {
    changes[id, default: 0] > savedChanges[id, default: 0] || unsaved[id] != nil
  }

  private struct SaveJob {
    let id: EpisodeID
    let change: Int
    let text: String
  }

  /// Copy the content to save as of now. The body is copied once per save, not per keystroke.
  private func makeSaveJob() -> SaveJob? {
    guard let id = episodeID, let textView, isDirty(id), conflicts[id] == nil else { return nil }
    return SaveJob(id: id, change: changes[id, default: 0], text: textView.string)
  }

  private func start(_ job: SaveJob) {
    if job.id == episodeID { waitingSince = nil }
    let key = UUID()
    inFlight[job.id] = job
    running[key] = Task {
      await write(job)
      running[key] = nil
    }
  }

  private func write(_ job: SaveJob) async {
    let store = store
    status = .saving
    let indicator = Task {
      try? await Task.sleep(for: .milliseconds(500))
      if !Task.isCancelled, status == .saving { showsSavingIndicator = true }
    }
    defer {
      indicator.cancel()
      showsSavingIndicator = false
    }
    let disk = disk
    do {
      // Pre-write check: compare disk against the baseline right before writing; don't write if it changed outside the app.
      let result = try await queue.save(.episode(job.id), change: job.change, writeReturning: {
        let result = try store.writeEpisode(job.text, id: job.id, ifUnchangedSince: disk[job.id])
        if case .written(let version) = result { disk[job.id] = version }
        return result
      }, didWrite: { if case .written = $0 { true } else { false } }, onRetry: { [weak self] in
        Task { @MainActor in
          if self?.status == .saving { self?.status = .retrying }
        }
      })
      if case .conflict(let diskVersion) = result {
        if inFlight[job.id]?.text == job.text { inFlight[job.id] = nil }
        raiseConflict(job.id, disk: diskVersion, appText: job.text)
        settleStatus()
        return
      }
      savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
      // If the in-memory body is older than what was just saved, its content is already on disk, so drop it.
      // (Drop it even if more was typed since. That text is in the editor and the next save handles it.)
      if let failed = unsaved[job.id], failed.change <= job.change { unsaved[job.id] = nil }
      if let backed = backedUp[job.id], backed <= job.change { removeBackup(job.id) }
      settleStatus()
    } catch {
      // If a newer body is already saved or held in memory, this failure is stale. Don't overwrite with the old body.
      if savedChanges[job.id, default: 0] < job.change, (unsaved[job.id]?.change ?? 0) <= job.change {
        unsaved[job.id] = job
        backUp(job)
        lastFailure = Failure(error)
      }
      settleStatus()
    }
    if inFlight[job.id]?.text == job.text { inFlight[job.id] = nil }
    releaseBaselineIfIdle(job.id)
  }

  // MARK: - Emergency backup (PLAN ch.17 #1)

  private func backUp(_ job: SaveJob) {
    guard let backup else { return }
    backedUp[job.id] = job.change
    let episodeTitle = episodeTitle(job.id)
    let projectTitle = projectTitle()
    let text = job.text
    let (id, change) = (job.id, job.change)
    enqueueBackup {
      try backup.write(text, episode: id, episodeTitle: episodeTitle, projectTitle: projectTitle)
    } done: { [weak self] written in
      self?.recordBackup(id, change: change, written: written)
    }
  }

  private func recordBackup(_ id: EpisodeID, change: Int, written: Bool) {
    // If it was saved meanwhile (backup deleted) or a newer backup started, this result is stale.
    guard backedUp[id] == change else { return }
    writtenBackups[id] = written ? change : nil
    if case .failed = status { settleStatus() }
  }

  private func removeBackup(_ id: EpisodeID) {
    writtenBackups[id] = nil
    guard let backup, backedUp.removeValue(forKey: id) != nil else { return }
    enqueueBackup { try backup.remove(id) }
  }

  /// Even if the backup can't be written, the manuscript stays in memory and the status bar shows the failure. `done` reports whether it was written.
  private func enqueueBackup(
    _ work: @escaping @Sendable () throws -> Void, done: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
  ) {
    let previous = backupTail
    backupTail = Task.detached(priority: .utility) {
      await previous?.value
      let written = (try? work()) != nil
      await done(written)
    }
  }

  /// Tests: until queued backup work finishes.
  func waitForBackups() async {
    await backupTail?.value
  }
}

/// All open autosavers. Used to finish pending saves at quit.
@MainActor
final class AutosaverRegistry {
  static let shared = AutosaverRegistry()
  private var items: [WeakAutosaver] = []

  private struct WeakAutosaver {
    weak var value: EpisodeAutosaver?
  }

  /// Autosavers whose window closed but still hold unsaved manuscripts. Kept so quit asks again.
  private var orphans: [EpisodeAutosaver] = []

  func register(_ autosaver: EpisodeAutosaver) {
    items.removeAll { $0.value == nil }
    items.append(WeakAutosaver(value: autosaver))
  }

  func keepAlive(_ autosaver: EpisodeAutosaver) {
    if !orphans.contains(where: { $0 === autosaver }) { orphans.append(autosaver) }
  }

  func release(_ autosaver: EpisodeAutosaver) {
    orphans.removeAll { $0 === autosaver }
  }

  var all: [EpisodeAutosaver] { items.compactMap(\.value) }
}
