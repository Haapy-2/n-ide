import Foundation
import NovelCore
import Observation

/// One open project's episode list and its saving. Handles adding, renaming, trashing and reordering episodes.
/// `project.json` saves go through the same save queue (`SaveQueue`) as body autosave to keep order.
@MainActor
@Observable
final class ProjectModel {
  private(set) var project: ProjectFile
  /// Description shown when a `project.json` save ultimately failed.
  var errorMessage: String?

  let store: ProjectStore
  @ObservationIgnored let queue: SaveQueue
  @ObservationIgnored let autosaver: EpisodeAutosaver
  @ObservationIgnored let counter: CharacterCounter
  @ObservationIgnored private var projectChange = 0
  /// Episodes being moved to the trash. Even before leaving the list, replace all won't write to them.
  @ObservationIgnored private var leaving: Set<EpisodeID> = []
  /// Number of unfinished `project.json` saves
  @ObservationIgnored private var projectSaves = 0
  /// Per-episode counts (for display). Inside `project`, every count change would recompute every view reading `project`
  /// (workspace + 500 sidebar rows; measured 17.5 ms, every 0.2 s while typing). So they're kept per episode
  /// so only that row redraws, and merged when writing `project.json`.
  @ObservationIgnored private var countBoxes: [EpisodeID: EpisodeCountBox] = [:]
  /// Move a file to the trash and return its new location there (to bring it back on undo).
  /// Tests swap this to move elsewhere instead of the real Trash.
  @ObservationIgnored private let moveToTrash: @Sendable (URL) throws -> URL
  /// Delay batching `project.json` saves when only counts changed (docs/PERFORMANCE.md ch.2).
  @ObservationIgnored private let countSaveDelay: Duration
  @ObservationIgnored private var countSave: Task<Void, Never>?
  @ObservationIgnored private var fileUndoTail: Task<Void, Never>?
  /// Number of unfinished undo file moves. Quit waits for them.
  @ObservationIgnored private var fileUndos = 0
  /// The last `project.json` save failed. Retried at quit; if it still fails, ask.
  @ObservationIgnored private var projectSaveFailed = false

  init(
    project: ProjectFile, store: ProjectStore, queue: SaveQueue = SaveQueue(),
    autosaveDelay: Duration = .seconds(1),
    countDelay: Duration = .milliseconds(200),
    countSaveDelay: Duration = .seconds(3),
    moveToTrash: @escaping @Sendable (URL) throws -> URL = ProjectModel.systemTrash,
    backup: EmergencyBackup? = nil
  ) {
    // Groups scattered by outside edits are fixed on open (episodes kept, only order gathered). Written to the file on the next save.
    var project = project
    let list = EpisodeGrouping.normalized(.init(episodes: project.episodes, groups: project.groups))
    project.episodes = list.episodes
    project.groups = list.groups
    self.project = project
    self.store = store
    self.queue = queue
    self.moveToTrash = moveToTrash
    self.countSaveDelay = countSaveDelay
    countBoxes = Dictionary(
      project.episodes.map { ($0.id, EpisodeCountBox($0.characterCount)) }, uniquingKeysWith: { first, _ in first })
    autosaver = EpisodeAutosaver(store: store, queue: queue, delay: autosaveDelay)
    counter = CharacterCounter(interval: countDelay)
    counter.onCount = { [weak self] id, count in self?.recordCount(count, for: id) }
    // Trash moves and undo file moves are included too. Quitting midway would leave files moved but still in the list (project.json).
    autosaver.hasProjectWork = { [weak self] in
      self.map {
        $0.countSave != nil || $0.projectSaves > 0 || $0.projectSaveFailed || !$0.leaving.isEmpty || $0.fileUndos > 0
      } ?? false
    }
    autosaver.finishProjectWork = { [weak self] in await self?.finishProjectSaves() }
    autosaver.episodeTitle = { [weak self] id in self?.project.episodes.first { $0.id == id }?.title ?? "" }
    autosaver.projectTitle = { [weak self] in self?.project.title ?? "" }
    // Inside init, plain `project` refers to the parameter (the list at open). The current list is `self.project`.
    autosaver.isListed = { [weak self] id in
      guard let self, !self.leaving.contains(id) else { return false }
      return self.project.episodes.contains { $0.id == id }
    }
    autosaver.backup = backup
  }

  var episodes: [EpisodeMeta] { project.episodes }

  /// Episode info (count is the current value). Calling this from a view's body would make that view redraw on this episode's count changes,
  /// so in bodies pass `countBox(for:)` to per-row views instead.
  func episode(_ id: EpisodeID) -> EpisodeMeta? {
    guard var episode = project.episodes.first(where: { $0.id == id }) else { return nil }
    if let box = countBoxes[id] { episode.characterCount = box.value }
    return episode
  }

  /// That episode's count box. Created if absent (new episode).
  func countBox(for id: EpisodeID) -> EpisodeCountBox {
    if let box = countBoxes[id] { return box }
    let box = EpisodeCountBox(nil)
    countBoxes[id] = box
    return box
  }

  // MARK: - Episode changes

  /// Create a new episode right after `after` (or at the end). Writes an empty body file first, then adds it to the list.
  /// With `undoManager`, ⌘Z sends the just-created episode to the trash (⇧⌘Z brings it back).
  @discardableResult
  func addEpisode(after: EpisodeID? = nil, undoManager: UndoManager? = nil) async throws -> EpisodeID {
    // Created after an episode in a group, it joins that group (continuing to the next chapter).
    let group = after.flatMap { id in project.episodes.first { $0.id == id }?.group }
    let episode = EpisodeMeta(title: "", goal: project.settings.defaultEpisodeGoal, group: group)
    let store = store
    let id = episode.id
    // The body file must exist first so there's never an episode in the list without a file.
    try await Task.detached { try store.writeEpisode("", id: id) }.value
    let index = after.flatMap { id in project.episodes.firstIndex { $0.id == id } }.map { $0 + 1 }
    let insertAt = index ?? project.episodes.endIndex
    project.episodes.insert(episode, at: insertAt)
    registerUndoByTrashing(TrashRecord(episode: episode, index: insertAt), actionName: "새 회차", undoManager: undoManager)
    await saveProject()
    return id
  }

  /// Why it was renamed. Appended to the rename snapshot memo (undo/redo are appended separately by checking `UndoManager`).
  enum RenameReason {
    case single
    case batch
    case restore
  }

  struct RenameOutcome: Equatable {
    var renamed = 0
    /// Number of episodes renamed whose snapshot couldn't be taken
    var unsnapshotted = 0
  }

  /// Rename (single, batch, snapshot restore). Trims whitespace and changes only episodes that actually change.
  /// Each changed episode gets a `rename` snapshot with its body and old title at that time. With `undoManager`, one ⌘Z
  /// reverts all, and undo/redo also take snapshots since they change names too.
  @discardableResult
  func renameEpisodes(
    _ titles: [EpisodeID: String], reason: RenameReason, undoManager: UndoManager? = nil
  ) async -> RenameOutcome {
    await applyRenames(titles, reason: reason, undoManager: undoManager).value
  }

  /// Batch rename sheet: apply the rule to the current list's titles in list order (reflecting titles changed after the sheet opened).
  @discardableResult
  func renameEpisodes(
    _ ids: Set<EpisodeID>, by rule: EpisodeTitleBatch.Rule, undoManager: UndoManager? = nil
  ) async -> RenameOutcome {
    let targets = project.episodes.filter { ids.contains($0.id) }
    let titles = EpisodeTitleBatch.titles(targets.map(\.title), by: rule)
    let renamed = Dictionary(zip(targets.map(\.id), titles), uniquingKeysWith: { first, _ in first })
    return await renameEpisodes(renamed, reason: .batch, undoManager: undoManager)
  }

  /// List change and undo registration happen in place (synchronously). Called again inside undo handling, so redo stacks up.
  private func applyRenames(
    _ titles: [EpisodeID: String], reason: RenameReason, undoManager: UndoManager?
  ) -> Task<RenameOutcome, Never> {
    var episodes = project.episodes
    var changes: [(id: EpisodeID, old: String, new: String)] = []
    for index in episodes.indices {
      guard let title = titles[episodes[index].id] else { continue }
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed != episodes[index].title else { continue }
      changes.append((episodes[index].id, episodes[index].title, trimmed))
      episodes[index].title = trimmed
    }
    guard !changes.isEmpty else { return Task { RenameOutcome() } }
    let tail: String? =
      if undoManager?.isUndoing == true { "되돌림" }
      else if undoManager?.isRedoing == true { "다시 실행" }
      else {
        switch reason {
        case .single: nil
        case .batch: changes.count > 1 ? "\(changes.count)개 회차 함께" : nil
        case .restore: "스냅샷 복원"
        }
      }
    let previous = Dictionary(changes.map { ($0.id, $0.old) }, uniquingKeysWith: { first, _ in first })
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated { _ = model.applyRenames(previous, reason: reason, undoManager: undoManager) }
    }
    undoManager?.setActionName(Self.renameActionName(count: changes.count))
    let save = replaceEpisodes(with: episodes, actionName: "", undoManager: nil)
    let date = Date()
    let snapshots = changes.map { change in
      let memo = "\(Self.quoted(change.old)) → \(Self.quoted(change.new))" + (tail.map { " · \($0)" } ?? "")
      return autosaver.snapshotRename(change.id, title: change.old, memo: memo, at: date)
    }
    return Task {
      var failed = 0
      for snapshot in snapshots {
        if (try? await snapshot.value) == nil { failed += 1 }
      }
      await save.value
      return RenameOutcome(renamed: changes.count, unsnapshotted: failed)
    }
  }

  static func renameActionName(count: Int) -> String { count > 1 ? "여러 회차 이름 변경" : "이름 변경" }

  private static func quoted(_ title: String) -> String { title.isEmpty ? "(제목 없음)" : "'\(title)'" }

  /// Episode goal character count. With `undoManager`, ⌘Z can revert it.
  func setGoal(_ id: EpisodeID, to goal: Int, undoManager: UndoManager? = nil) async {
    guard goal > 0, let index = project.episodes.firstIndex(where: { $0.id == id }),
      project.episodes[index].goal != goal
    else { return }
    var episodes = project.episodes
    episodes[index].goal = goal
    await replaceEpisodes(with: episodes, actionName: "목표 글자 수", undoManager: undoManager).value
  }

  /// Project default goal (used for new episodes, per-project setting in project.json). With `undoManager`, ⌘Z can revert it.
  /// The undo record is registered in place (synchronously). Called in the same moment as the episode goal, one ⌘Z reverts both.
  @discardableResult
  func setDefaultEpisodeGoal(_ goal: Int, undoManager: UndoManager? = nil) -> Task<Void, Never> {
    let previous = project.settings.defaultEpisodeGoal
    guard goal > 0, goal != previous else { return Task {} }
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated { model.setDefaultEpisodeGoal(previous, undoManager: undoManager) }
    }
    undoManager?.setActionName("목표 글자 수")
    project.settings.defaultEpisodeGoal = goal
    return startProjectSave()
  }

  /// Change all episode goals at once (Settings "apply to all episodes"). One ⌘Z reverts all.
  func setGoalForAllEpisodes(_ goal: Int, undoManager: UndoManager? = nil) async {
    guard goal > 0, project.episodes.contains(where: { $0.goal != goal }) else { return }
    let episodes = project.episodes.map { episode in
      var episode = episode
      episode.goal = goal
      return episode
    }
    await replaceEpisodes(with: episodes, actionName: "모든 회차 목표", undoManager: undoManager).value
  }

  /// Reorder by drag. Positions are the sidebar's visible row indices (including group headers, `EpisodeGrouping.rows`),
  /// and the moved episode's group is set by the drop position (`EpisodeGrouping.drop`). With `undoManager`, ⌘Z restores the previous order.
  func moveEpisodes(
    rows source: IndexSet, before destination: Int, collapsed: Set<GroupID> = [], undoManager: UndoManager? = nil
  ) async {
    let next = EpisodeGrouping.drop(source, before: destination, in: list, collapsed: collapsed)
    guard next != list else { return }
    await replaceList(next, actionName: "순서 변경", undoManager: undoManager).value
  }

  // MARK: - Episode groups (PLAN ch.8 option B)

  /// Make the chosen episodes a new group. If scattered, gathered at the first episode's position. Returns the new group's ID.
  @discardableResult
  func groupEpisodes(_ ids: Set<EpisodeID>, title: String, undoManager: UndoManager? = nil) async -> GroupID? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !ids.isEmpty else { return nil }
    let group = EpisodeGroup(title: trimmed.isEmpty ? "새 묶음" : trimmed)
    await replaceList(EpisodeGrouping.group(ids, as: group, in: list), actionName: "묶기", undoManager: undoManager).value
    return group.id
  }

  func ungroup(_ group: GroupID, undoManager: UndoManager? = nil) async {
    await replaceList(EpisodeGrouping.ungroup(group, in: list), actionName: "묶음 풀기", undoManager: undoManager).value
  }

  func renameGroup(_ group: GroupID, to title: String, undoManager: UndoManager? = nil) async {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let index = project.groups.firstIndex(where: { $0.id == group }),
      project.groups[index].title != trimmed
    else { return }
    var next = list
    next.groups[index].title = trimmed
    await replaceList(next, actionName: "묶음 이름 변경", undoManager: undoManager).value
  }

  func addEpisodes(_ ids: Set<EpisodeID>, to group: GroupID, undoManager: UndoManager? = nil) async {
    let next = EpisodeGrouping.add(ids, to: group, in: list)
    guard next != list else { return }
    await replaceList(next, actionName: "묶음에 넣기", undoManager: undoManager).value
  }

  private var list: EpisodeGrouping.List { .init(episodes: project.episodes, groups: project.groups) }

  /// Replace the whole episode list (order, titles) and start saving. Undo records the list before the change.
  /// This function is called again inside undo handling, so redo (⇧⌘Z) stacks up automatically.
  /// Registration must happen in place (synchronously) for UndoManager to tell undo from redo correctly.
  /// Only the episode list changes, not files, so undoing doesn't affect bodies.
  @discardableResult
  private func replaceEpisodes(
    with episodes: [EpisodeMeta], actionName: String, undoManager: UndoManager?
  ) -> Task<Void, Never> {
    replaceList(.init(episodes: episodes, groups: project.groups), actionName: actionName, undoManager: undoManager)
  }

  /// Change the episode list and group names together. Undo reverts both.
  @discardableResult
  private func replaceList(
    _ list: EpisodeGrouping.List, actionName: String, undoManager: UndoManager?
  ) -> Task<Void, Never> {
    let previous = self.list
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated {
        // Revert only if it's the same set of episodes, so episodes added or deleted meanwhile aren't overwritten.
        guard Set(model.project.episodes.map(\.id)) == Set(previous.episodes.map(\.id)) else { return }
        model.replaceList(previous, actionName: actionName, undoManager: undoManager)
      }
    }
    undoManager?.setActionName(actionName)
    // Counts aren't part of undo. The separately held current values (countBoxes) go in at save time.
    project.episodes = list.episodes
    project.groups = list.groups
    return startProjectSave()
  }

  /// Names of picture files just added to `images/` (decision 52). Not part of undo: the file stays after ⌘Z (G2), and so does its name.
  func addImageNames(_ images: [ImageMeta]) {
    let known = Set(project.images.map(\.id))
    let added = images.filter { !known.contains($0.id) }
    guard !added.isEmpty else { return }
    project.images += added
    _ = startProjectSave()
  }

  /// Move an episode to the trash. If it can't be trashed, change nothing and throw (no permanent delete as a substitute).
  /// With `undoManager`, ⌘Z takes it out of the trash back to its original position.
  func trashEpisode(_ id: EpisodeID, undoManager: UndoManager? = nil) async throws {
    guard let index = project.episodes.firstIndex(where: { $0.id == id }) else { return }
    let record = TrashRecord(episode: project.episodes[index], index: index)
    try await moveToTrash(record)
    registerUndoByRestoring(record, actionName: "휴지통으로 이동", undoManager: undoManager)
  }

  /// Append episode files missing from `project.json` (`unlistedEpisodes`) at the end as "recovered episodes" and save. Returns how many.
  /// Called after the project opens without blocking the screen. Episodes created or trashed during the search aren't added.
  func adoptUnlistedEpisodes() async -> Int {
    let store = store
    let listed = Set(project.episodes.map(\.id))
    guard let found = try? await Task.detached(operation: { try store.unlistedEpisodes(excluding: listed) }).value
    else { return 0 }
    let fresh = found.filter { id in
      !project.episodes.contains { $0.id == id }
        && FileManager.default.fileExists(atPath: store.layout.episodeFile(id).path(percentEncoded: false))
    }
    guard !fresh.isEmpty else { return 0 }
    let goal = project.settings.defaultEpisodeGoal
    project.episodes += fresh.map { EpisodeMeta(id: $0, title: "되찾은 회차", goal: goal) }
    await saveProject()
    return fresh.count
  }

  // MARK: - Trash and undo

  /// Record of one trashed (or to-be-trashed) episode. Undo and redo pass the same record back and forth.
  final class TrashRecord {
    let episode: EpisodeMeta
    let index: Int
    /// Location inside the trash. Has a value only while in the trash.
    var trashedURL: URL?

    init(episode: EpisodeMeta, index: Int) {
      self.episode = episode
      self.index = index
    }
  }

  private func moveToTrash(_ record: TrashRecord) async throws {
    let id = record.episode.id
    // While waiting for the save and moving the file, the episode stays in the list. If replace all started writing in that gap,
    // a new body file would appear at the old spot, so mark it "leaving" first to block new writes (writes already started are awaited by flush).
    leaving.insert(id)
    defer { leaving.remove(id) }
    // Save edits before deleting, so the latest content is there when restored from the trash.
    await autosaver.flush()
    // If it still couldn't be saved, don't move it. Moving would send only the old body to the trash and discard the latest manuscript in memory.
    guard autosaver.pendingText(for: id) == nil else { throw UnsavedEpisodeError() }
    let file = store.layout.episodeFile(id)
    let moveToTrash = moveToTrash
    record.trashedURL = try await Task.detached {
      FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? try moveToTrash(file) : nil
    }.value
    autosaver.forget(episode: id)
    project.episodes.removeAll { $0.id == id }
    await saveProject()
  }

  /// Take it out of the trash back to its original position (the end if the list shrank). Never overwrite an existing file of the same name.
  private func restoreFromTrash(_ record: TrashRecord) async throws {
    guard !project.episodes.contains(where: { $0.id == record.episode.id }) else { return }
    if let trashed = record.trashedURL {
      let destination = store.layout.episodeFile(record.episode.id)
      try await Task.detached { try FileManager.default.moveItem(at: trashed, to: destination) }.value
      record.trashedURL = nil
    }
    project.episodes.insert(record.episode, at: min(record.index, project.episodes.count))
    // If group shapes changed meanwhile, regather to satisfy the group rule (contiguous episodes).
    let list = EpisodeGrouping.normalized(.init(episodes: project.episodes, groups: project.groups))
    project.episodes = list.episodes
    project.groups = list.groups
    await saveProject()
  }

  // Undo registration must happen in place (synchronously). File moves happen afterwards in a Task.
  // That way UndoManager stacks undo and redo correctly.

  /// Register ⌘Z to send this episode to the trash (undo of new episode, redo of restore-from-trash).
  private func registerUndoByTrashing(_ record: TrashRecord, actionName: String, undoManager: UndoManager?) {
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated {
        model.registerUndoByRestoring(record, actionName: actionName, undoManager: undoManager)
        model.enqueueFileUndo { try await model.moveToTrash(record) }
      }
    }
    undoManager?.setActionName(actionName)
  }

  /// Register ⌘Z to take this episode out of the trash (undo of move-to-trash, redo of new episode).
  private func registerUndoByRestoring(_ record: TrashRecord, actionName: String, undoManager: UndoManager?) {
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated {
        model.registerUndoByTrashing(record, actionName: actionName, undoManager: undoManager)
        model.enqueueFileUndo { try await model.restoreFromTrash(record) }
      }
    }
    undoManager?.setActionName(actionName)
  }

  /// File moves run one at a time in press order. Pressing ⌘Z/⇧⌘Z quickly in a row would let separate tasks interleave,
  /// leaving an episode in the list whose file is in the trash.
  private func enqueueFileUndo(_ work: @escaping () async throws -> Void) {
    let previous = fileUndoTail
    fileUndos += 1
    fileUndoTail = Task {
      await previous?.value
      do {
        try await work()
      } catch {
        errorMessage = "되돌리지 못했어요. 파일은 그대로 두었어요. \(error.localizedDescription)"
      }
      fileUndos -= 1
    }
  }

  /// Wait until all undo-initiated file moves finish. The last item in the queue waits for earlier ones and the list save after them.
  func finishFileUndos() async {
    await fileUndoTail?.value
  }

  nonisolated static func systemTrash(_ url: URL) throws -> URL {
    var resulting: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    guard let resulting else { throw CocoaError(.fileWriteUnknown) }
    return resulting as URL
  }

  // MARK: - Character count

  /// Record counted values in the episode list. Only when changed, and `project.json` saves are deferred and batched.
  /// (To avoid writing on every pause in typing. If the app quits before saving, reopening that episode recounts.)
  func recordCount(_ count: CharacterCount, for id: EpisodeID) {
    guard project.episodes.contains(where: { $0.id == id }) else { return }
    let box = countBox(for: id)
    guard box.value != count else { return }
    box.value = count
    guard countSave == nil else { return }
    countSave = Task { [countSaveDelay] in
      try? await Task.sleep(for: countSaveDelay)
      guard !Task.isCancelled else { return }
      countSave = nil
      await saveProject()
    }
  }

  /// Perform the deferred count save now (on window close).
  func saveCountsNow() async {
    guard let task = countSave else { return }
    task.cancel()
    countSave = nil
    await saveProject()
  }

  // MARK: - Saving

  /// Wait for trash/undo file moves, perform the deferred count save now, and wait until all started `project.json` saves
  /// finish (window close, quit).
  /// So the changed list is on disk even if the app quits right after a rename.
  func finishProjectSaves() async {
    await finishFileUndos()
    while !leaving.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
    await saveCountsNow()
    while projectSaves > 0 {
      try? await Task.sleep(for: .milliseconds(2))
    }
    // Nobody retries an earlier failed save, so try once more here.
    if projectSaveFailed { await saveProject() }
  }

  /// Only start the save and return. It counts as "unfinished" from the moment it starts (so quitting right after still waits).
  private func startProjectSave() -> Task<Void, Never> {
    projectSaves += 1
    return Task {
      await saveProject()
      projectSaves -= 1
    }
  }

  private func saveProject() async {
    projectSaves += 1
    defer { projectSaves -= 1 }
    projectChange += 1
    let change = projectChange
    var merged = project
    for index in merged.episodes.indices {
      if let box = countBoxes[merged.episodes[index].id] { merged.episodes[index].characterCount = box.value }
    }
    let snapshot = merged
    let store = store
    do {
      _ = try await queue.save(.project, change: change) { try store.saveProject(snapshot) }
      projectSaveFailed = false
      errorMessage = nil
    } catch {
      projectSaveFailed = true
      let reason = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      errorMessage = "회차 목록(project.json)을 저장하지 못했어요. \(reason)"
    }
  }
}

/// The latest manuscript of the episode being trashed couldn't be saved yet (disk full, no permission etc.).
struct UnsavedEpisodeError: LocalizedError {
  var errorDescription: String? { "이 회차의 마지막 원고를 아직 저장하지 못했어요. 저장된 뒤에 다시 시도해 주세요." }
}

/// Box holding one episode's count. When it changes, only views reading this box (that sidebar row) redraw.
@MainActor
@Observable
final class EpisodeCountBox {
  var value: CharacterCount?
  init(_ value: CharacterCount?) { self.value = value }
}
