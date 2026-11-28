import NovelCore
import SwiftUI

/// Workspace for one project: glass sidebar (episode list) + opaque paper editor area.
struct WorkspaceView: View {
  /// nil is for previews/snapshots: bodies aren't read and the list can't change.
  private let model: ProjectModel?
  private let previewProject: ProjectFile?
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var sidebarSeesThroughWindow = true
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var goalBasis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.collapsedEpisodeGroups) private var collapsedText = ""
  @State private var selection: EpisodeID?
  /// Multiple selected episodes (⌘-click, ⇧-click). Used for grouping.
  @State private var marked: Set<EpisodeID> = []
  /// Shared by the View menu (⌥⌘S) and the toolbar sidebar button.
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  /// Episodes to group (name prompt is up)
  @State private var grouping: Set<EpisodeID>?
  @State private var renamingGroup: GroupID?
  @State private var groupTitle = ""
  @State private var renaming: EpisodeID?
  @State private var renameText = ""
  @State private var batchRenaming: BatchRenameSheet.Request?
  @State private var trashing: EpisodeID?
  @State private var settingGoal: EpisodeID?
  @State private var goalText = ""
  @State private var alertMessage: String?
  /// Snapshot to attach a memo to. Filled when the toast's "메모 달기" is pressed; when non-nil the memo field appears.
  @State private var memoTarget: Snapshot?
  /// Toast at the top right of the editor (⌘S save, take snapshot).
  @State private var toasts = ToastCenter()
  @State private var memoText = ""
  /// Open snapshot panel (⇧⌘S). nil = closed.
  @State private var snapshotBrowser: SnapshotBrowser?
  /// Whether the editor had focus when the panel opened. Focus is returned there on close.
  @State private var editorHadFocus = false
  /// Whether the editor had focus when the search panel opened. Returned there on close (same as the snapshot panel).
  @State private var searchTookEditorFocus = false
  /// Sidebar undo awaiting confirmation. When non-nil the confirmation appears.
  @State private var pendingUndo: PendingUndo?
  @State private var stopAskingUndo = false
  /// Project search. Created on first open; phrase and results remain after closing (resumes on reopen).
  @State private var search: ProjectSearch?
  /// Project-wide replace. Created together with search.
  @State private var replace: ProjectReplace?
  /// Open replace-all revert sheet. nil = closed.
  @State private var revertSession: RevertSession?
  /// Episode chosen in the replaced-episodes list. The snapshot panel opens after its body is loaded into the editor.
  @State private var snapshotRequest: SnapshotRequest?
  @State private var showingSearch = false
  /// Measured left padding for both sidebar panels. Kept here so it survives panel switches (EpisodeList.measuredInset).
  @State private var listInset: CGFloat?
  @State private var searchInset: CGFloat?
  /// Incremented on every ⇧⌘F to focus the input field.
  @State private var searchFocusRequest = 0
  /// Go to a search result. Handled after the editor loads that episode's body.
  @State private var reveal: TextReveal?
  /// The window's undo history. The editor keeps per-episode histories, so ⌘Z uses this when the sidebar has focus.
  @Environment(\.undoManager) private var undoManager
  /// When this window comes to the front (key window), Settings shows this project's goal.
  @Environment(\.appearsActive) private var appearsActive

  init(model: ProjectModel) {
    self.model = model
    previewProject = nil
    let ids = model.episodes.map(\.id)
    _selection = State(initialValue: EpisodeViewStates.shared.lastOpened(among: ids) ?? ids.first)
  }

  init(previewProject: ProjectFile) {
    model = nil
    self.previewProject = previewProject
    _selection = State(initialValue: previewProject.episodes.first?.id)
  }

  private var project: ProjectFile { model?.project ?? previewProject! }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      sidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    } detail: {
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        .overlay { ToastOverlay(center: toasts) }
        // Title and buttons attach to the editor-side toolbar. On the sidebar side only the sidebar width shows, cutting long titles.
        .navigationTitle(project.title)
        .navigationSubtitle(selectedEpisodeLabel)
        .toolbar {
          ToolbarItem {
            Button("새 회차", systemImage: "square.and.pencil") { addEpisode(after: selection) }
              .disabled(model == nil)
          }
          ToolbarItem {
            Button("작품 전체 검색", systemImage: "magnifyingglass") { openSearch() }
              .disabled(model == nil)
          }
        }
    }
    .overlay {
      if let snapshotBrowser {
        SnapshotPanel(
          browser: snapshotBrowser, title: snapshotPanelTitle,
          hasConflict: model?.autosaver.conflicts[snapshotBrowser.episodeID] != nil,
          onClose: closeSnapshots, onRestore: restoreSnapshot)
      }
    }
    .frame(minWidth: 720, minHeight: 480)
    // Making the window background a translucent material lets other apps and the desktop show through the floating glass sidebar.
    // The paper (editor area) is opaque paper color, so nothing shows through on the body side.
    .modifier(SeeThroughWindowBackground(isEnabled: sidebarSeesThroughWindow))
    // Lets the episode menu (EpisodeCommands) send commands to the front window's workspace.
    .focusedSceneValue(\.workspaceActions, model == nil ? nil : actions)
    .alert("회차 이름", isPresented: isRenaming) {
      TextField("제목", text: $renameText)
      Button("변경") { commitRename() }
      Button("취소", role: .cancel) { renaming = nil }
    } message: {
      Text("비워 두면 \"제목 없음\"으로 보여요.")
    }
    .alert(groupingTitle, isPresented: isNamingGroup) {
      TextField("묶음 이름", text: $groupTitle)
      Button(renamingGroup == nil ? "묶기" : "변경") { commitGroupTitle() }
      Button("취소", role: .cancel) {
        grouping = nil
        renamingGroup = nil
      }
    } message: {
      Text(renamingGroup == nil ? "떨어져 있는 회차는 맨 앞 회차 자리로 모여요. ⌘Z로 되돌릴 수 있어요." : "")
    }
    .alert("목표 글자 수", isPresented: isSettingGoal) {
      TextField("글자 수", text: $goalText)
      Button("이 회차만") { commitGoal(alsoForNewEpisodes: false) }
      Button("새 회차에도 쓰기") { commitGoal(alsoForNewEpisodes: true) }
      Button("취소", role: .cancel) { settingGoal = nil }
    } message: {
      Text("\(goalBasis.title) 기준으로 셉니다. 지금 새 회차는 \(project.settings.defaultEpisodeGoal.formatted())자로 시작해요.")
    }
    .modifier(undoConfirmationDialog)
    .alert("스냅샷 메모", isPresented: isWritingMemo) {
      TextField("메모 (선택)", text: $memoText)
      Button("확인") { commitMemo() }
      Button("메모 없이", role: .cancel) { memoTarget = nil }
    } message: {
      Text("나중에 알아보기 쉽게 한 줄 남길 수 있어요.")
    }
    .alert(trashTitle, isPresented: isTrashing) {
      Button("휴지통으로 이동", role: .destructive) { commitTrash() }
      Button("취소", role: .cancel) { trashing = nil }
    } message: {
      Text("본문 파일을 휴지통으로 옮겨요. 휴지통에서 꺼내면 되살릴 수 있어요.")
    }
    .alert(conflictTitle, isPresented: isShowingConflict, presenting: readyConflict) { conflict in
      Button("이 앱의 내용 쓰기") { Task { await model?.autosaver.keepAppVersion(conflict.episodeID) } }
      Button("바깥에서 바뀐 내용 쓰기") { Task { await model?.autosaver.useDiskVersion(conflict.episodeID) } }
    } message: { conflict in
      Text(conflictMessage(conflict))
    }
    .alert("알림", isPresented: isShowingAlert) {
      Button("확인") { alertMessage = nil; model?.errorMessage = nil }
    } message: {
      Text(alertMessage ?? model?.errorMessage ?? "")
    }
    .sheet(item: $batchRenaming) { request in
      BatchRenameSheet(
        episodes: project.episodes, targetIDs: request.episodeIDs, onCancel: { batchRenaming = nil },
        onRename: { rule in
          batchRenaming = nil
          renameBatch(request.episodeIDs, by: rule)
        })
    }
    .sheet(item: $revertSession) { session in
      RevertSheet(
        session: session, episodes: project.episodes, onCancel: { revertSession = nil },
        onRevert: { ids in
          revertSession = nil
          performRevert(session.undoable.record, ids)
        })
    }
    // If editor ⌘Z undid only the open episode's replace all, say the other episodes can be reverted too.
    .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { note in
      guard let manager = note.object as? UndoManager, let model, model.autosaver.ownsEditorUndo(manager),
        manager.redoActionName == ProjectReplace.actionName, let replace, let last = replace.history.last
      else { return }
      toasts.show(
        "이 회차만 되돌렸어요", systemImage: "arrow.uturn.backward",
        action: last.entries.count > 1 ? .init(title: "모든 회차 되돌리기") { beginRevert() } : nil,
        duration: .seconds(5))
    }
    // Close the panel when leaving the episode it was showing (moving via menu/shortcut or trashing it).
    .onChange(of: selection) {
      if snapshotBrowser?.episodeID != selection { closeSnapshots() }
      if snapshotRequest?.episodeID != selection { snapshotRequest = nil }
      // Moving episodes via menu/shortcut/search shrinks a multi-selection to that one episode.
      if let selection, !marked.contains(selection) { marked = [selection] }
    }
    .onChange(of: project.episodes.map(\.id)) { old, new in
      (selection, marked) = Self.afterListChange(selection: selection, marked: marked, old: old, new: new) {
        EpisodeViewStates.shared.lastOpened(among: new) ?? new.first
      }
    }
    // Finish pending saves on window close (a Task retains the saver, so saving completes even after the window is gone).
    .onChange(of: appearsActive, initial: true) {
      if appearsActive, let model { ActiveWorkspace.shared.activate(model, undoManager: undoManager) }
    }
    .onDisappear {
      if let model { ActiveWorkspace.shared.deactivate(model) }
      if let model {
        // Leave snapshot and save start now while the editor still exists; only waiting for completion is in the Task.
        model.autosaver.startFinishing()
        Task { await Self.finishClosing(model) }
      }
    }
  }

  /// Sidebar slot: the episode list, or the search panel (⇧⌘F).
  @ViewBuilder
  private var sidebar: some View {
    if showingSearch, let search, let replace {
      SearchPanel(
        search: search, replace: replace, episodes: project.episodes, focusRequest: searchFocusRequest,
        measuredInset: $searchInset,
        onReveal: { target in
          // Results are re-searched when the episode list changes, but a result clicked before that finishes may point at a deleted episode.
          guard project.episodes.contains(where: { $0.id == target.episodeID }) else { return }
          selection = target.episodeID
          reveal = target
        },
        onReplaced: { report in
          let first = replace.finished?.replaced.first
          toasts.show(
            ProjectReplace.summary(of: report),
            action: first.map { entry in .init(title: "바꾼 곳 보기") { showReplaced(entry) } },
            secondAction: report.count > 0 ? .init(title: "되돌리기") { beginRevert() } : nil,
            duration: report.count > 0 ? .seconds(5) : nil)
          if report.count > 0 { registerReplaceUndo(replace) }
          search.refresh()
        },
        onShowReplaced: { showReplaced($0) },
        onClose: { closeSearch() })
    } else {
      EpisodeList(
        episodes: project.episodes,
        groups: project.groups,
        selection: $selection,
        marked: $marked,
        measuredInset: $listInset,
        onRename: model == nil ? nil : { beginRename($0) },
        onBatchRename: model == nil ? nil : { batchRenaming = .init(episodeIDs: $0) },
        onTrash: model == nil ? nil : { trashing = $0 },
        onSetGoal: model == nil ? nil : { beginSetGoal($0) },
        onAddAfter: model == nil ? nil : { id in addEpisode(after: id) },
        onMove: model == nil ? nil : { source, destination in
          Task {
            await model?.moveEpisodes(
              rows: source, before: destination, collapsed: EpisodeList.collapsedGroups(collapsedText),
              undoManager: undoManager)
          }
        },
        onGroup: model == nil ? nil : { beginGrouping($0) },
        onUngroup: model == nil ? nil : { group in Task { await model?.ungroup(group, undoManager: undoManager) } },
        onRenameGroup: model == nil ? nil : { beginRenamingGroup($0) },
        onAddToGroup: model == nil ? nil : { ids, group in
          Task { await model?.addEpisodes(ids, to: group, undoManager: undoManager) }
        },
        onUndoCommand: model == nil ? nil : { requestUndo(isRedo: $0) },
        countBox: model.map { model in { model.countBox(for: $0) } })
    }
  }

  /// Selection after the episode list changes (trash, ⌘Z, outside edits). If the viewed episode vanished, the one at the same position (or above);
  /// if nothing is selected but the list isn't empty (last episode restored with ⌘Z), `fallback`. A multi-selection keeps only remaining episodes.
  static func afterListChange(
    selection: EpisodeID?, marked: Set<EpisodeID>, old: [EpisodeID], new: [EpisodeID],
    whenNothingSelected fallback: () -> EpisodeID?
  ) -> (selection: EpisodeID?, marked: Set<EpisodeID>) {
    let remaining = marked.intersection(new)
    guard let current = selection else { return (new.isEmpty ? nil : fallback(), remaining) }
    guard !new.contains(current) else { return (current, remaining) }
    let oldIndex = old.firstIndex(of: current) ?? 0
    return (new.isEmpty ? nil : new[min(oldIndex, new.count - 1)], remaining)
  }

  // MARK: - Episode groups

  private func beginGrouping(_ ids: Set<EpisodeID>) {
    guard !ids.isEmpty else { return }
    groupTitle = ""
    renamingGroup = nil
    grouping = ids
  }

  private func beginRenamingGroup(_ group: GroupID) {
    groupTitle = project.groups.first { $0.id == group }?.title ?? ""
    grouping = nil
    renamingGroup = group
  }

  private var groupingTitle: String {
    if renamingGroup != nil { return "묶음 이름" }
    return (grouping?.count ?? 0) > 1 ? "\(grouping?.count ?? 0)개 회차 묶기" : "묶기"
  }

  private var isNamingGroup: Binding<Bool> {
    Binding(get: { grouping != nil || renamingGroup != nil }, set: { if !$0 { grouping = nil; renamingGroup = nil } })
  }

  private func commitGroupTitle() {
    let title = groupTitle
    if let group = renamingGroup {
      Task { await model?.renameGroup(group, to: title, undoManager: undoManager) }
    } else if let ids = grouping {
      Task { await model?.groupEpisodes(ids, title: title, undoManager: undoManager) }
    }
    grouping = nil
    renamingGroup = nil
  }

  private func openSearch() {
    guard let model, snapshotBrowser == nil else { return }
    if search == nil {
      let autosaver = model.autosaver
      search = ProjectSearch(
        store: model.store, episodeIDs: { model.episodes.map(\.id) }, texts: { autosaver.searchTexts() })
      replace = ProjectReplace(
        store: model.store, autosaver: autosaver, episodeIDs: { model.episodes.map(\.id) },
        recordCount: { model.recordCount($0, for: $1) })
    }
    if !showingSearch { searchTookEditorFocus = model.autosaver.yieldFocus() }
    // The search panel appears in the sidebar slot, so with the sidebar hidden it must be shown.
    if columnVisibility == .detailOnly { columnVisibility = .all }
    showingSearch = true
    searchFocusRequest += 1
  }

  private func closeSearch() {
    showingSearch = false
    if searchTookEditorFocus { model?.autosaver.regainFocus() }
    searchTookEditorFocus = false
  }

  @ViewBuilder
  private var detail: some View {
    if project.episodes.isEmpty {
      EmptyStateView(message: "첫 회차를 추가해 주세요.", buttonTitle: "새 회차", action: model == nil ? nil : { addEpisode(after: nil) })
    } else if let model, let selection {
      EpisodeEditorPane(
        autosaver: model.autosaver, counter: model.counter, episodeID: selection,
        goal: project.episodes.first { $0.id == selection }?.goal ?? 0,
        // Counts aren't read in body (reading them would recompute the whole workspace on every count change).
        knownCount: { model.countBox(for: selection).value },
        reveal: reveal,
        onShown: { episodeShown($0) },
        onNotice: { toasts.show($0, systemImage: "exclamationmark.circle") },
        onImagesAdded: { model.addImageNames($0) })
    } else {
      Color.clear
    }
  }

  // MARK: - Episode commands

  private var actions: WorkspaceActions {
    // While the snapshot panel is open, commands that change body or title are blocked. The panel's "current" is the body and title at open time.
    let panelOpen = snapshotBrowser != nil
    return WorkspaceActions(
      addEpisode: { addEpisode(after: selection) },
      renameSelected: panelOpen ? nil : selection.map { id in { beginRename(id) } },
      trashSelected: selection.map { id in { trashing = id } },
      trashTitle: trashMenuTitle,
      setGoalSelected: selection.map { id in { beginSetGoal(id) } },
      selectPrevious: neighbor(step: -1),
      selectNext: neighbor(step: 1),
      saveNow: model.map { model in { saveNow(model) } },
      saveWithSnapshot: model.map { model in { saveWithSnapshot(model) } },
      takeSnapshot: selection == nil || snapshotBrowser != nil ? nil : { takeSnapshot() },
      showSnapshots: selection == nil || snapshotBrowser != nil ? nil : { showSnapshots() },
      showSearch: panelOpen ? nil : { openSearch() },
      revertReplace: !panelOpen && replace?.history.isEmpty == false ? { beginRevert() } : nil,
      groupMarked: selection == nil ? nil : { beginGrouping(marked.isEmpty ? Set([selection].compactMap { $0 }) : marked) },
      ungroupSelected: selection.flatMap { id in project.episodes.first { $0.id == id }?.group }.map { group in
        { Task { await model?.ungroup(group, undoManager: undoManager) } }
      },
      toggleSidebar: { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly },
      isSidebarVisible: columnVisibility != .detailOnly)
  }

  /// Command moving to the visible episode before (-1) / after (+1) the selected one (skipping collapsed groups). nil if none.
  /// Menu previous/next episode follows project order. Going into a collapsed group makes the sidebar expand it (EpisodeList.show).
  /// Sidebar ↑↓ follows only visible rows (EpisodeList.move).
  private func neighbor(step: Int) -> (() -> Void)? {
    let episodes = project.episodes
    guard let selection, let index = episodes.firstIndex(where: { $0.id == selection }),
      episodes.indices.contains(index + step)
    else { return nil }
    let id = episodes[index + step].id
    return { self.selection = id }
  }

  private func addEpisode(after id: EpisodeID?) {
    guard let model else { return }
    Task {
      do {
        selection = try await model.addEpisode(after: id, undoManager: undoManager)
      } catch {
        alertMessage = "새 회차를 만들지 못했어요. \((error as? ProjectError)?.userMessage ?? error.localizedDescription)"
      }
    }
  }

  /// ⌘S. No toast for autosave (SPEC ch.5); "저장했어요" only when pressed manually and successful.
  /// Failures and external-change conflicts are already reported by the status bar and dialogs, so no toast.
  private func saveNow(_ model: ProjectModel) {
    Task {
      await model.autosaver.flush()
      let hasConflict = selection.map { model.autosaver.conflicts[$0] != nil } ?? false
      if model.autosaver.status == .idle, !hasConflict {
        toasts.show("저장했어요")
      }
    }
  }

  /// Snapshot on save (⌘S when enabled in Settings). No snapshot if saving fails (the status bar reports the failure).
  /// If the text equals the last snapshot, just "저장했어요" without a snapshot.
  private func saveWithSnapshot(_ model: ProjectModel) {
    Task {
      await model.autosaver.flush()
      let hasConflict = selection.map { model.autosaver.conflicts[$0] != nil } ?? false
      guard model.autosaver.status == .idle, !hasConflict else { return }
      do {
        if let snapshot = try await model.autosaver.takeManualSnapshot(skipIfUnchanged: true) {
          toasts.show("스냅샷 저장됨", action: memoAction(for: snapshot))
        } else {
          toasts.show("저장했어요")
        }
      } catch {
        alertMessage = "저장은 했지만 스냅샷을 찍지 못했어요. \((error as? ProjectError)?.userMessage ?? error.localizedDescription)"
      }
    }
  }

  private func memoAction(for snapshot: Snapshot) -> Toast.Action {
    Toast.Action(title: "메모 달기") {
      memoText = ""
      memoTarget = snapshot
    }
  }

  /// Finish saving first, snapshot, then show the toast. The memo field appears only when "메모 달기" is pressed (to interrupt writing less).
  private func takeSnapshot() {
    guard let model else { return }
    Task {
      do {
        guard let snapshot = try await model.autosaver.takeManualSnapshot() else { return }
        toasts.show("스냅샷을 찍었어요", action: memoAction(for: snapshot))
      } catch {
        alertMessage = "스냅샷을 찍지 못했어요. \((error as? ProjectError)?.userMessage ?? error.localizedDescription)"
      }
    }
  }

  /// Before opening the panel, end editor composition and release focus. The current body is copied once here.
  private func showSnapshots(preferring preferredID: String? = nil) {
    guard let model, let id = selection, snapshotBrowser == nil, let editor = model.autosaver.beginPanel() else { return }
    editorHadFocus = editor.hadFocus
    let browser = SnapshotBrowser(
      store: model.store, episodeID: id, currentText: editor.text, currentTitle: model.episode(id)?.title ?? "",
      preferredID: preferredID)
    snapshotBrowser = browser
    Task { await browser.load() }
  }

  // MARK: - Revert replace all (PLAN ch.14 #5)

  /// Open the revert sheet (toast, Edit menu, ⌘Z in sidebar/search panel). Operations that changed just one episode revert directly without a sheet.
  private func beginRevert() {
    guard let replace, revertSession == nil else { return }
    Task {
      guard let found = await replace.latestUndoable() else {
        toasts.show("되돌릴 곳이 없어요", systemImage: "arrow.uturn.backward")
        return
      }
      if found.record.entries.count == 1 {
        performRevert(found.record, Set(found.candidates.map(\.id)))
      } else {
        revertSession = RevertSession(found, replace: replace)
      }
    }
  }

  private func performRevert(_ record: ProjectReplace.Record, _ ids: Set<EpisodeID>) {
    guard let replace else { return }
    Task {
      let report = await replace.revert(record, ids)
      // The search panel's "N곳을 바꿨어요" no longer holds, so clear it and search again on the current text.
      replace.clearFinished()
      toasts.show(
        ProjectReplace.summary(of: report, redo: false), systemImage: "arrow.uturn.backward",
        action: replace.reverted == nil ? nil : .init(title: "다시 바꾸기") { redoReplace() },
        duration: .seconds(5))
      search?.refresh()
    }
  }

  private func redoReplace() {
    guard let replace else { return }
    Task {
      guard let report = await replace.redo() else { return }
      replace.clearFinished()
      toasts.show(ProjectReplace.summary(of: report, redo: true))
      search?.refresh()
    }
  }

  /// Also recorded in the window's undo history: ⌘Z in the sidebar/search panel opens the revert sheet in order with episode actions.
  /// After the sheet opens, redo replace stays in the redo slot (does nothing if no episodes were reverted).
  private func registerReplaceUndo(_ replace: ProjectReplace) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: replace) { replace in
      MainActor.assumeIsolated {
        beginRevert()
        registerReplaceRedo(replace)
      }
    }
    undoManager.setActionName(ProjectReplace.actionName)
  }

  private func registerReplaceRedo(_ replace: ProjectReplace) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: replace) { replace in
      MainActor.assumeIsolated {
        redoReplace()
        registerReplaceUndo(replace)
      }
    }
    undoManager.setActionName(ProjectReplace.actionName)
  }

  /// Replaced-episodes list (or the toast's "바꾼 곳 보기"): go to that episode and open the snapshot panel with `바꾸기 전` preselected.
  /// The panel compares with the current body, so after moving episodes it opens once that body is loaded in the editor (`onShown`).
  private func showReplaced(_ entry: ProjectReplace.Report.Episode) {
    guard project.episodes.contains(where: { $0.id == entry.id }) else { return }
    closeSnapshots()
    let request = SnapshotRequest(episodeID: entry.id, preferredID: entry.before?.id)
    if selection == entry.id, model?.autosaver.episodeID == entry.id {
      showSnapshots(preferring: request.preferredID)
    } else {
      snapshotRequest = request
      selection = entry.id
    }
  }

  private func episodeShown(_ id: EpisodeID) {
    guard let request = snapshotRequest, request.episodeID == id, selection == id else { return }
    snapshotRequest = nil
    showSnapshots(preferring: request.preferredID)
  }

  private func closeSnapshots() {
    guard let browser = snapshotBrowser else { return }
    browser.cancel()
    snapshotBrowser = nil
    model?.autosaver.endPanel(hadFocus: editorHadFocus)
  }

  /// Restore to the chosen snapshot and close the panel. The caret returns to the editor and "취소" appears in the status bar.
  private func restoreSnapshot() {
    guard let model, let browser = snapshotBrowser else { return }
    Task {
      let restored = await browser.restoreSelected(with: model.autosaver) { title in
        await model.renameEpisodes([browser.episodeID: title], reason: .restore, undoManager: undoManager)
        toasts.show("제목도 되돌렸어요", systemImage: "arrow.uturn.backward")
      }
      guard restored, snapshotBrowser === browser else { return }
      // The restored body no longer matches the search panel's last result ("N곳을 바꿨어요", matched lines).
      replace?.clearFinished()
      search?.refresh()
      browser.cancel()
      snapshotBrowser = nil
      model.autosaver.endPanel(hadFocus: true)
    }
  }

  private var selectedEpisodeLabel: String {
    guard let selection, let index = project.episodes.firstIndex(where: { $0.id == selection }) else { return "" }
    return EpisodeLabel.text(number: index + 1, title: project.episodes[index].title)
  }

  private var snapshotPanelTitle: String {
    guard let id = snapshotBrowser?.episodeID, let index = project.episodes.firstIndex(where: { $0.id == id }) else {
      return "스냅샷"
    }
    let title = project.episodes[index].title
    return "스냅샷 · \(EpisodeLabel.text(number: index + 1, title: title))"
  }

  private func commitMemo() {
    guard let model, let snapshot = memoTarget else { return }
    memoTarget = nil
    let store = model.store
    let memo = memoText
    Task {
      do {
        try await Task.detached { try store.writeMemo(memo, for: snapshot) }.value
      } catch {
        alertMessage = "메모를 남기지 못했어요. 스냅샷은 남아 있어요."
      }
    }
  }

  private func beginRename(_ id: EpisodeID) {
    renameText = model?.episode(id)?.title ?? ""
    renaming = id
  }

  private func renameBatch(_ ids: Set<EpisodeID>, by rule: EpisodeTitleBatch.Rule) {
    guard let model else { return }
    Task {
      let outcome = await model.renameEpisodes(ids, by: rule, undoManager: undoManager)
      guard outcome.renamed > 0 else { return }
      var message = "\(outcome.renamed.formatted())개 회차 이름을 바꿨어요"
      if outcome.unsnapshotted > 0 { message += " · \(outcome.unsnapshotted.formatted())개는 스냅샷을 못 남겼어요" }
      // If another action reached the top of the undo stack meanwhile, don't undo it.
      toasts.show(
        message,
        action: .init(title: "되돌리기") {
          if undoManager?.undoActionName == ProjectModel.renameActionName(count: outcome.renamed) { undoManager?.undo() }
        },
        duration: .seconds(5))
    }
  }

  private func commitRename() {
    guard let model, let id = renaming else { return }
    renaming = nil
    Task { await model.renameEpisodes([id: renameText], reason: .single, undoManager: undoManager) }
  }

  private func beginSetGoal(_ id: EpisodeID) {
    goalText = String(model?.episode(id)?.goal ?? 5_000)
    settingGoal = id
  }

  // MARK: - Sidebar undo confirmation

  /// Sidebar undo confirmation. Split out because the body was too long for the compiler to type-check at once.
  private var undoConfirmationDialog: UndoConfirmationDialog {
    UndoConfirmationDialog(pending: $pendingUndo, stopAsking: $stopAskingUndo, perform: performUndo)
  }

  struct PendingUndo {
    let isRedo: Bool
    let actionName: String

    var title: String {
      let name = actionName.isEmpty ? "마지막 작업" : actionName
      let quoted = actionName.isEmpty ? name : "\"\(name)\""
      return isRedo ? "\(quoted)\(Self.objectParticle(name)) 다시 실행할까요?" : "\(quoted)\(Self.objectParticle(name)) 되돌릴까요?"
    }

    /// "을" if the last character has a final consonant, otherwise "를". E.g. 이름 변경을, 새 회차를
    static func objectParticle(_ word: String) -> String {
      guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "을" }
      return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }
  }

  /// Do nothing if there's nothing to undo. Revert directly if the confirmation is resting.
  private func requestUndo(isRedo: Bool) {
    guard let undoManager, isRedo ? undoManager.canRedo : undoManager.canUndo else { return }
    let pending = PendingUndo(isRedo: isRedo, actionName: isRedo ? undoManager.redoActionName : undoManager.undoActionName)
    // For replace all, the revert sheet replaces the confirmation.
    if UndoConfirmation.isPaused() || pending.actionName == ProjectReplace.actionName {
      performUndo(pending)
    } else {
      stopAskingUndo = false
      pendingUndo = pending
    }
  }

  private func performUndo(_ pending: PendingUndo) {
    pendingUndo = nil
    if stopAskingUndo { UndoConfirmation.pause() }
    if pending.isRedo { undoManager?.redo() } else { undoManager?.undo() }
  }

  /// Accept digits only (commas and "자" ignored). Don't change for ≤ 0 or non-numbers.
  /// With `alsoForNewEpisodes`, also set the project default goal (project.json) to the same value. Chosen in the same dialog to avoid more menu items.
  private func commitGoal(alsoForNewEpisodes: Bool) {
    guard let model, let id = settingGoal else { return }
    settingGoal = nil
    guard let goal = Int(goalText.filter(\.isNumber)), goal > 0 else { return }
    // Both undo records must be registered in the same turn so one ⌘Z reverts both.
    Task {
      if alsoForNewEpisodes { model.setDefaultEpisodeGoal(goal, undoManager: undoManager) }
      await model.setGoal(id, to: goal, undoManager: undoManager)
    }
  }

  /// Finish pending saves on window close. Ask if a manuscript or the episode list ultimately couldn't be written.
  static func finishClosing(
    _ model: ProjectModel, retryProjectSave: @MainActor () -> Bool = SystemDialogs.retryProjectSaveOnClose
  ) async {
    await model.autosaver.finish()
    await model.saveCountsNow()
    rescueUnsaved(model)
    // If the episode list (project.json) ultimately failed, ask whether to retry as at quit. Closing without asking would silently lose list changes.
    while model.autosaver.hasProjectWork(), retryProjectSave() {
      await model.finishProjectSaves()
    }
  }

  /// If unsaved manuscripts remain after closing the window, ask whether to export elsewhere.
  /// If not exported, retain the saver so quit can ask again (if it vanished with the window, the manuscript would vanish too).
  private static func rescueUnsaved(_ model: ProjectModel) {
    let autosaver = model.autosaver
    // Episodes intact in a conflict snapshot aren't manuscripts to export (same criterion as quit).
    guard autosaver.hasUnprotectedChanges else { return }
    // The project model vanishes with the window, so grab the title now.
    let titles = Dictionary(model.episodes.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    autosaver.episodeTitle = { titles[$0] ?? "" }
    if SystemDialogs.offerRescueOnClose(autosaver.unsavedManuscripts()) {
      autosaver.markRescued()
    } else {
      AutosaverRegistry.shared.keepAlive(autosaver)
    }
  }

  private func commitTrash() {
    guard let model, let id = trashing else { return }
    trashing = nil
    let episodes = project.episodes
    let index = episodes.firstIndex { $0.id == id }
    Task {
      do {
        try await model.trashEpisode(id, undoManager: undoManager)
        // If the deleted episode was being viewed, move to the one right below (or above).
        if selection == id, let index {
          let remaining = model.episodes
          selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
      } catch {
        alertMessage = "휴지통으로 옮기지 못해 지우지 않았어요. \(error.localizedDescription)"
      }
    }
  }

  /// Trash applies only to the current episode, so with multiple selected the menu title says so (grouping applies to all selected).
  private var trashMenuTitle: String? {
    guard marked.count > 1, let selection, let index = project.episodes.firstIndex(where: { $0.id == selection }) else {
      return nil
    }
    return "지금 회차(\(index + 1)화)만 휴지통으로 이동…"
  }

  private var trashTitle: String {
    guard let id = trashing, let index = project.episodes.firstIndex(where: { $0.id == id }) else { return "" }
    let title = project.episodes[index].title
    let name = EpisodeLabel.text(number: index + 1, title: title, quoted: true)
    return "\(KoreanParticle.attach(.objectMarker, to: name)) 휴지통으로 옮길까요?"
  }

  // MARK: - External-change conflicts

  /// One conflict to ask the user about, fully snapshotted.
  private var readyConflict: EpisodeAutosaver.Conflict? {
    model?.autosaver.conflicts.values.first { $0.isReady }
  }

  private var conflictTitle: String {
    guard let id = readyConflict?.episodeID, let index = project.episodes.firstIndex(where: { $0.id == id }) else {
      return "회차 파일이 앱 밖에서 바뀌었어요"
    }
    let title = project.episodes[index].title
    return "\(EpisodeLabel.text(number: index + 1, title: title, quoted: true)) 파일이 앱 밖에서 바뀌었어요"
  }

  private func conflictMessage(_ conflict: EpisodeAutosaver.Conflict) -> String {
    let kept = conflict.snapshot.map { "이 앱에서 쓰던 내용은 스냅샷(\($0.lastPathComponent))으로 남겨 두었어요." }
      ?? "이 앱에서 쓰던 내용을 스냅샷으로 남기지 못했어요. 고르기 전까지 메모리에 들고 있어요."
    let stopped: String? =
      switch conflict.unkept {
      case .app: "이 앱에서 쓴 내용을 스냅샷으로 남기지 못해 바꾸지 않았어요."
      case .disk: "바깥에서 바뀐 내용을 스냅샷으로 남기지 못해 덮어쓰지 않았어요."
      case nil: nil
      }
    let retry = stopped.map { "\n\n\($0) 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 골라 주세요." } ?? ""
    return "이 앱에서도 고친 내용이 있어서 덮어쓰지 않았어요. \(kept)\n어느 쪽을 쓸까요? 고르지 않은 쪽도 스냅샷으로 남아요."
      + retry
  }

  /// One of the two must be chosen. Just closing makes it reappear.
  private var isShowingConflict: Binding<Bool> {
    Binding(get: { readyConflict != nil }, set: { _ in })
  }

  private var isWritingMemo: Binding<Bool> {
    Binding(get: { memoTarget != nil }, set: { if !$0 { memoTarget = nil } })
  }

  private var isRenaming: Binding<Bool> {
    Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
  }

  private var isSettingGoal: Binding<Bool> {
    Binding(get: { settingGoal != nil }, set: { if !$0 { settingGoal = nil } })
  }

  private var isTrashing: Binding<Bool> {
    Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })
  }

  private var isShowingAlert: Binding<Bool> {
    Binding(
      get: { alertMessage != nil || model?.errorMessage != nil },
      set: { if !$0 { alertMessage = nil; model?.errorMessage = nil } })
  }
}

/// When on, the window background is a translucent material showing what's behind; when off, the system default (opaque) background.
private struct SeeThroughWindowBackground: ViewModifier {
  let isEnabled: Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content.containerBackground(.ultraThinMaterial, for: .window)
    } else {
      content
    }
  }
}

#Preview("빈 작품") {
  WorkspaceView(previewProject: ProjectFile(title: "회귀한 검성은 이번 생에서만큼은 조용히 살고 싶다"))
    .frame(width: 1100, height: 760)
}

#Preview("500회차") {
  WorkspaceView(previewProject: .previewManyEpisodes)
    .frame(width: 1100, height: 760)
}

extension ProjectFile {
  /// 500-episode project for previews and snapshots (no bodies).
  static var previewManyEpisodes: ProjectFile {
    let titles = ["귀환", "비 오는 날", "", "검의 무게", "첫 번째 의뢰", "달빛 아래에서"]
    return ProjectFile(
      title: "달빛 아래 검",
      episodes: (0..<500).map { EpisodeMeta(title: titles[$0 % titles.count], goal: 5_000) })
  }
}

/// Request to open the snapshot panel for an episode chosen in the replaced-episodes list.
private struct SnapshotRequest {
  let episodeID: EpisodeID
  let preferredID: String?
}

/// Sidebar undo confirmation (macOS standard confirmation + "don't ask again" checkbox).
private struct UndoConfirmationDialog: ViewModifier {
  @Binding var pending: WorkspaceView.PendingUndo?
  @Binding var stopAsking: Bool
  let perform: (WorkspaceView.PendingUndo) -> Void

  /// The confirmation is attached to an empty background. `dialogSuppressionToggle` is an environment value, so applying it to the whole workspace
  /// would add "don't ask again" to other confirmations inside it too (replace all, episode name etc.).
  func body(content: Content) -> some View {
    content.background { dialogHost }
  }

  private var dialogHost: some View {
    Color.clear
      .confirmationDialog(
        pending?.title ?? "",
        isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
        titleVisibility: .visible, presenting: pending
      ) { pending in
        // Return goes to Cancel. Revert by click or Tab → Space.
        Button("취소", role: .cancel) { self.pending = nil }
          .keyboardShortcut(.defaultAction)
        Button(pending.isRedo ? "다시 실행" : "되돌리기") { perform(pending) }
      } message: { _ in
        Text("회차 목록이 바뀌기 전으로 돌아가요. 본문은 바뀌지 않아요.")
      }
      .dialogSuppressionToggle("다시 묻지 않기", isSuppressed: $stopAsking)
  }
}
