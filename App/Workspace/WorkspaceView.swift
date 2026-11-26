import NovelCore
import SwiftUI

/// 작품 하나의 작업 공간: 유리 사이드바(회차 목록) + 불투명 종이 편집 영역.
struct WorkspaceView: View {
  /// nil이면 미리보기·스냅샷용이라 본문을 읽지 않고 목록을 바꿀 수 없다.
  private let model: ProjectModel?
  private let previewProject: ProjectFile?
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var sidebarSeesThroughWindow = true
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var goalBasis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.collapsedEpisodeGroups) private var collapsedText = ""
  @State private var selection: EpisodeID?
  /// 여러 개 고른 회차(⌘클릭·⇧클릭). 묶기에 쓴다.
  @State private var marked: Set<EpisodeID> = []
  /// 묶을 회차(이름 묻는 창이 떠 있음)
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
  /// 메모를 달 스냅샷. 토스트의 "메모 달기"를 누르면 채워지고, nil이 아니면 메모 칸이 뜬다.
  @State private var memoTarget: Snapshot?
  /// 편집 영역 오른쪽 위 토스트(⌘S 저장, 스냅샷 찍기).
  @State private var toasts = ToastCenter()
  @State private var memoText = ""
  /// 열려 있는 스냅샷 판(⇧⌘S). nil이면 닫힘.
  @State private var snapshotBrowser: SnapshotBrowser?
  /// 판을 열 때 편집기가 초점을 갖고 있었는지. 닫을 때 그 자리로 돌려준다.
  @State private var editorHadFocus = false
  /// 검색 패널을 열 때 편집기가 초점을 갖고 있었는지. 닫을 때 그 자리로 돌려준다(스냅샷 판과 같다).
  @State private var searchTookEditorFocus = false
  /// 확인을 기다리는 사이드바 되돌리기. nil이 아니면 확인 창이 뜬다.
  @State private var pendingUndo: PendingUndo?
  @State private var stopAskingUndo = false
  /// 작품 전체 검색. 처음 열 때 만들고, 패널을 닫아도 문구와 결과는 남긴다(다시 열면 이어서).
  @State private var search: ProjectSearch?
  /// 작품 전체 바꾸기. 검색과 함께 만든다.
  @State private var replace: ProjectReplace?
  /// 열려 있는 전체 바꾸기 되돌리기 창. nil이면 닫힘.
  @State private var revertSession: RevertSession?
  /// 바꾼 회차 목록에서 고른 회차. 편집기에 그 회차 본문이 올라간 뒤 스냅샷 판을 연다.
  @State private var snapshotRequest: SnapshotRequest?
  @State private var showingSearch = false
  /// 사이드바 두 패널의 잰 왼쪽 여백. 패널이 바뀌어도 남아야 해서 여기 둔다(EpisodeList.measuredInset).
  @State private var listInset: CGFloat?
  @State private var searchInset: CGFloat?
  /// ⇧⌘F를 누를 때마다 늘려 입력 칸에 초점을 준다.
  @State private var searchFocusRequest = 0
  /// 검색 결과로 가기. 편집기가 그 회차의 본문을 올린 뒤 처리한다.
  @State private var reveal: TextReveal?
  /// 창의 실행 취소 기록. 편집기는 회차별로 따로 갖고 있어서, 사이드바에 초점이 있을 때 ⌘Z가 이것을 쓴다.
  @Environment(\.undoManager) private var undoManager
  /// 이 창이 앞(키 창)에 오면 설정 창이 이 작품의 목표를 보여 준다.
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
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    } detail: {
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        .overlay { ToastOverlay(center: toasts) }
        // 제목과 버튼을 편집 영역 쪽 툴바에 붙인다. 사이드바 쪽에 두면 사이드바 폭만큼만 보여서 긴 제목이 잘린다.
        .navigationTitle(project.title)
        .toolbar {
          ToolbarItem {
            Button("새 회차", systemImage: "square.and.pencil") { addEpisode(after: selection) }
              .disabled(model == nil)
          }
          ToolbarItem {
            Button("작품 전체 검색", systemImage: "magnifyingglass") { openSearch() }
              .disabled(model == nil)
          }
          ToolbarItem {
            Button("노트 나란히 보기", systemImage: "sidebar.right") {}
              .disabled(true)
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
    // 창 바탕을 반투명 재질로 바꾸면 그 위에 떠 있는 유리 사이드바로 창 뒤의 다른 앱과 바탕화면이 비친다.
    // 종이(편집 영역)는 불투명 paper 색이라 본문 쪽은 비치지 않는다.
    .modifier(SeeThroughWindowBackground(isEnabled: sidebarSeesThroughWindow))
    // 회차 메뉴(EpisodeCommands)가 지금 앞에 있는 창의 작업 공간에 명령을 보낼 수 있게 한다.
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
    // 편집기 ⌘Z로 열린 회차의 전체 바꾸기만 되돌렸으면 다른 회차도 되돌릴 수 있다고 알린다.
    .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { note in
      guard let manager = note.object as? UndoManager, let model, model.autosaver.ownsEditorUndo(manager),
        manager.redoActionName == ProjectReplace.actionName, let replace, let last = replace.history.last
      else { return }
      toasts.show(
        "이 회차만 되돌렸어요", systemImage: "arrow.uturn.backward",
        action: last.entries.count > 1 ? .init(title: "모든 회차 되돌리기") { beginRevert() } : nil,
        duration: .seconds(5))
    }
    // 판이 보고 있던 회차에서 벗어나면(메뉴·단축키로 회차를 옮기거나 휴지통으로 보냄) 판을 닫는다.
    .onChange(of: selection) {
      if snapshotBrowser?.episodeID != selection { closeSnapshots() }
      if snapshotRequest?.episodeID != selection { snapshotRequest = nil }
      // 메뉴·단축키·검색으로 회차를 옮기면 여러 개 고른 것을 그 회차 하나로 줄인다.
      if let selection, !marked.contains(selection) { marked = [selection] }
    }
    .onChange(of: project.episodes.map(\.id)) { old, new in
      (selection, marked) = Self.afterListChange(selection: selection, marked: marked, old: old, new: new) {
        EpisodeViewStates.shared.lastOpened(among: new) ?? new.first
      }
    }
    // 창을 닫을 때 남은 저장을 마친다(Task가 저장기를 붙잡고 있어 창이 사라져도 끝까지 저장된다).
    .onChange(of: appearsActive, initial: true) {
      if appearsActive, let model { ActiveWorkspace.shared.activate(model, undoManager: undoManager) }
    }
    .onDisappear {
      if let model { ActiveWorkspace.shared.deactivate(model) }
      if let model {
        // 떠날 때 스냅샷과 저장은 편집기가 아직 있는 지금 시작하고, 끝나기를 기다리는 것만 Task로 한다.
        model.autosaver.startFinishing()
        Task { await Self.finishClosing(model) }
      }
    }
  }

  /// 사이드바 자리: 회차 목록, 또는 검색 패널(⇧⌘F).
  @ViewBuilder
  private var sidebar: some View {
    if showingSearch, let search, let replace {
      SearchPanel(
        search: search, replace: replace, episodes: project.episodes, focusRequest: searchFocusRequest,
        measuredInset: $searchInset,
        onReveal: { target in
          // 결과는 회차 목록이 바뀌면 다시 찾지만, 다시 찾기가 끝나기 전에 누른 결과는 지운 회차를 가리킬 수 있다.
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

  /// 회차 목록이 바뀐 뒤(휴지통, ⌘Z, 앱 밖에서 고침)의 선택. 보던 회차가 사라지면 같은 자리(없으면 위) 회차로,
  /// 고른 회차가 없는데 목록이 비지 않았으면(마지막 회차를 ⌘Z로 되살림) `fallback`으로. 여러 개 고른 것은 남은 회차만.
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

  // MARK: - 회차 묶음

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
        // 글자 수는 body에서 읽지 않는다(읽으면 글자 수가 바뀔 때마다 작업 공간 전체가 다시 계산된다).
        knownCount: { model.countBox(for: selection).value },
        reveal: reveal,
        onShown: { episodeShown($0) },
        onNotice: { toasts.show($0, systemImage: "exclamationmark.circle") })
    } else {
      Color.clear
    }
  }

  // MARK: - 회차 명령

  private var actions: WorkspaceActions {
    // 스냅샷 판이 열린 동안에는 본문·제목을 바꾸는 명령을 막는다. 판의 "현재"는 판을 연 때의 본문과 제목이다.
    let panelOpen = snapshotBrowser != nil
    return WorkspaceActions(
      addEpisode: { addEpisode(after: selection) },
      renameSelected: panelOpen ? nil : selection.map { id in { beginRename(id) } },
      trashSelected: selection.map { id in { trashing = id } },
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
      })
  }

  /// 선택한 회차의 앞(-1)·뒤(+1)에 보이는 회차로 옮기는 명령(접힌 묶음 안은 건너뜀). 없으면 nil.
  private func neighbor(step: Int) -> (() -> Void)? {
    guard let selection,
      let id = EpisodeGrouping.visibleNeighbor(
        of: selection, step: step, in: .init(episodes: project.episodes, groups: project.groups),
        collapsed: EpisodeList.collapsedGroups(collapsedText))
    else { return nil }
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

  /// ⌘S. 자동 저장에는 토스트를 띄우지 않고(SPEC 5장), 직접 눌러 성공했을 때만 "저장했어요".
  /// 실패나 외부 변경 충돌은 지금처럼 상태 줄·확인 창이 알려 주므로 토스트를 띄우지 않는다.
  private func saveNow(_ model: ProjectModel) {
    Task {
      await model.autosaver.flush()
      let hasConflict = selection.map { model.autosaver.conflicts[$0] != nil } ?? false
      if model.autosaver.status == .idle, !hasConflict {
        toasts.show("저장했어요")
      }
    }
  }

  /// 저장하면서 스냅샷 찍기(설정에서 켰을 때 ⌘S). 저장이 실패하면 찍지 않는다(실패는 상태 줄이 알림).
  /// 글이 마지막 스냅샷과 같으면 찍지 않고 "저장했어요"만.
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

  /// 저장을 먼저 끝내고 찍은 뒤 토스트를 띄운다. 메모 칸은 "메모 달기"를 누를 때만 뜬다(글 흐름을 덜 끊으려고).
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

  /// 판을 열기 전에 편집기의 조합을 끝내고 초점을 내려놓는다. 지금 본문은 이때 한 번만 복사한다.
  private func showSnapshots(preferring preferredID: String? = nil) {
    guard let model, let id = selection, snapshotBrowser == nil, let editor = model.autosaver.beginPanel() else { return }
    editorHadFocus = editor.hadFocus
    let browser = SnapshotBrowser(
      store: model.store, episodeID: id, currentText: editor.text, currentTitle: model.episode(id)?.title ?? "",
      preferredID: preferredID)
    snapshotBrowser = browser
    Task { await browser.load() }
  }

  // MARK: - 전체 바꾸기 되돌리기 (PLAN 14장 5번)

  /// 되돌리기 창을 연다(토스트, 편집 메뉴, 사이드바·검색 패널의 ⌘Z). 한 회차만 바꾼 작업은 창 없이 바로 되돌린다.
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
      toasts.show(ProjectReplace.summary(of: report, redo: true))
      search?.refresh()
    }
  }

  /// 창의 실행 취소 기록에도 남긴다: 사이드바·검색 패널의 ⌘Z가 회차 작업과 순서대로 되돌리기 창을 연다.
  /// 창을 연 뒤에는 다시 실행 자리에 다시 바꾸기가 남는다(되돌린 회차가 없으면 아무것도 하지 않는다).
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

  /// 바꾼 회차 목록(또는 토스트의 "바꾼 곳 보기"): 그 회차로 옮기고 스냅샷 판을 `바꾸기 전`을 골라 둔 채 연다.
  /// 판은 지금 본문과 비교하므로, 회차를 옮겼으면 편집기에 그 본문이 올라간 뒤(`onShown`) 연다.
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

  /// 고른 스냅샷으로 되돌리고 판을 닫는다. 커서는 편집기로 돌아가고 상태 줄에 "취소"가 뜬다.
  private func restoreSnapshot() {
    guard let model, let browser = snapshotBrowser else { return }
    Task {
      let restored = await browser.restoreSelected(with: model.autosaver) { title in
        await model.renameEpisodes([browser.episodeID: title], reason: .restore, undoManager: undoManager)
        toasts.show("제목도 되돌렸어요", systemImage: "arrow.uturn.backward")
      }
      guard restored, snapshotBrowser === browser else { return }
      browser.cancel()
      snapshotBrowser = nil
      model.autosaver.endPanel(hadFocus: true)
    }
  }

  private var snapshotPanelTitle: String {
    guard let id = snapshotBrowser?.episodeID, let index = project.episodes.firstIndex(where: { $0.id == id }) else {
      return "스냅샷"
    }
    let title = project.episodes[index].title
    return "스냅샷 · \(index + 1)화\(title.isEmpty ? "" : " \(title)")"
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
      // 그사이 다른 작업이 실행 취소 맨 위에 올라왔으면 그것을 되돌리지 않는다.
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

  // MARK: - 사이드바 되돌리기 확인

  /// 사이드바 되돌리기 확인 창. 본문(body)이 길어 컴파일러가 한 번에 못 풀어서 따로 뺐다.
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

    /// 마지막 글자에 받침이 있으면 "을", 없으면 "를". 예: 이름 변경을, 새 회차를
    static func objectParticle(_ word: String) -> String {
      guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "을" }
      return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }
  }

  /// 되돌릴 것이 없으면 아무것도 하지 않는다. 확인 창이 쉬는 중이면 바로 되돌린다.
  private func requestUndo(isRedo: Bool) {
    guard let undoManager, isRedo ? undoManager.canRedo : undoManager.canUndo else { return }
    let pending = PendingUndo(isRedo: isRedo, actionName: isRedo ? undoManager.redoActionName : undoManager.undoActionName)
    // 전체 바꾸기는 되돌리기 창이 확인을 대신한다.
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

  /// 숫자만 받는다(쉼표·"자"는 무시). 0 이하나 숫자가 아니면 바꾸지 않는다.
  /// `alsoForNewEpisodes`면 작품 기본 목표(project.json)도 같은 값으로 바꾼다. 메뉴 항목을 늘리지 않으려고 같은 창에서 고른다.
  private func commitGoal(alsoForNewEpisodes: Bool) {
    guard let model, let id = settingGoal else { return }
    settingGoal = nil
    guard let goal = Int(goalText.filter(\.isNumber)), goal > 0 else { return }
    // 두 되돌리기 기록을 같은 차례 안에서 남겨야 ⌘Z 한 번에 함께 되돌아간다.
    Task {
      if alsoForNewEpisodes { model.setDefaultEpisodeGoal(goal, undoManager: undoManager) }
      await model.setGoal(id, to: goal, undoManager: undoManager)
    }
  }

  /// 창을 닫을 때 남은 저장을 마친다. 원고나 회차 목록을 끝내 쓰지 못했으면 묻는다.
  static func finishClosing(
    _ model: ProjectModel, retryProjectSave: @MainActor () -> Bool = SystemDialogs.retryProjectSaveOnClose
  ) async {
    await model.autosaver.finish()
    await model.saveCountsNow()
    rescueUnsaved(model)
    // 회차 목록(project.json)을 끝내 못 썼으면 종료 때처럼 다시 시도할지 묻는다. 묻지 않고 닫으면 목록 변경이 조용히 사라진다.
    while model.autosaver.hasProjectWork(), retryProjectSave() {
      await model.finishProjectSaves()
    }
  }

  /// 창을 닫았는데도 저장하지 못한 원고가 남았으면 다른 곳에 내보낼지 묻는다.
  /// 안 내보내면 앱을 끌 때 다시 물을 수 있게 저장기를 붙잡아 둔다(창과 함께 사라지면 원고도 사라진다).
  private static func rescueUnsaved(_ model: ProjectModel) {
    let autosaver = model.autosaver
    // 충돌 스냅샷에 그대로 남은 회차는 내보낼 원고가 아니다(종료 때와 같은 기준).
    guard autosaver.hasUnprotectedChanges else { return }
    // 작품 모델은 창과 함께 사라지므로 제목을 지금 붙잡아 둔다.
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
        // 지운 회차를 보고 있었으면 바로 아래(없으면 위) 회차로 옮긴다.
        if selection == id, let index {
          let remaining = model.episodes
          selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
      } catch {
        alertMessage = "휴지통으로 옮기지 못해 지우지 않았어요. \(error.localizedDescription)"
      }
    }
  }

  private var trashTitle: String {
    guard let id = trashing, let index = project.episodes.firstIndex(where: { $0.id == id }) else { return "" }
    let title = project.episodes[index].title
    return "\(index + 1)화\(title.isEmpty ? "" : " ‘\(title)’")을(를) 휴지통으로 옮길까요?"
  }

  // MARK: - 외부 변경 충돌

  /// 스냅샷을 다 남긴, 사용자에게 물을 충돌 하나.
  private var readyConflict: EpisodeAutosaver.Conflict? {
    model?.autosaver.conflicts.values.first { $0.isReady }
  }

  private var conflictTitle: String {
    guard let id = readyConflict?.episodeID, let index = project.episodes.firstIndex(where: { $0.id == id }) else {
      return "회차 파일이 앱 밖에서 바뀌었어요"
    }
    let title = project.episodes[index].title
    return "\(index + 1)화\(title.isEmpty ? "" : " ‘\(title)’") 파일이 앱 밖에서 바뀌었어요"
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

  /// 반드시 둘 중 하나를 골라야 한다. 닫기만 하면 다시 뜬다.
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

/// 켜져 있으면 창 바탕을 창 뒤가 비치는 반투명 재질로, 꺼져 있으면 시스템 기본(불투명) 바탕으로.
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
  /// 미리보기와 스냅샷용 500회차 작품 (본문 없음).
  static var previewManyEpisodes: ProjectFile {
    let titles = ["귀환", "비 오는 날", "", "검의 무게", "첫 번째 의뢰", "달빛 아래에서"]
    return ProjectFile(
      title: "달빛 아래 검",
      episodes: (0..<500).map { EpisodeMeta(title: titles[$0 % titles.count], goal: 5_000) })
  }
}

/// 바꾼 회차 목록에서 고른 회차의 스냅샷 판 열기 요청.
private struct SnapshotRequest {
  let episodeID: EpisodeID
  let preferredID: String?
}

/// 사이드바 되돌리기 확인 창(맥 기본 확인 창 + "다시 묻지 않기" 체크).
private struct UndoConfirmationDialog: ViewModifier {
  @Binding var pending: WorkspaceView.PendingUndo?
  @Binding var stopAsking: Bool
  let perform: (WorkspaceView.PendingUndo) -> Void

  /// 확인 창을 빈 뒷배경에 단다. `dialogSuppressionToggle`은 환경값이라 작업 공간 전체에 걸면
  /// 그 안의 다른 확인 창(전체 바꾸기, 회차 이름 등)에도 "다시 묻지 않기"가 붙는다.
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
        // 엔터는 취소가 받는다. 되돌리기는 클릭이나 Tab → Space로.
        Button("취소", role: .cancel) { self.pending = nil }
          .keyboardShortcut(.defaultAction)
        Button(pending.isRedo ? "다시 실행" : "되돌리기") { perform(pending) }
      } message: { _ in
        Text("회차 목록이 바뀌기 전으로 돌아가요. 본문은 바뀌지 않아요.")
      }
      .dialogSuppressionToggle("다시 묻지 않기", isSuppressed: $stopAsking)
  }
}
