import NovelCore
import SwiftUI

/// 작품 하나의 작업 공간: 유리 사이드바(회차 목록) + 불투명 종이 편집 영역.
struct WorkspaceView: View {
  /// nil이면 미리보기·스냅샷용이라 본문을 읽지 않고 목록을 바꿀 수 없다.
  private let model: ProjectModel?
  private let previewProject: ProjectFile?
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var sidebarSeesThroughWindow = true
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var goalBasis: CharacterCountBasis = .withSpaces
  @State private var selection: EpisodeID?
  /// 여러 개 고른 회차(⌘클릭·⇧클릭). 묶기에 쓴다.
  @State private var marked: Set<EpisodeID> = []
  /// 묶을 회차(이름 묻는 창이 떠 있음)
  @State private var grouping: Set<EpisodeID>?
  @State private var renamingGroup: GroupID?
  @State private var groupTitle = ""
  @State private var renaming: EpisodeID?
  @State private var renameText = ""
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
  /// 확인을 기다리는 사이드바 되돌리기. nil이 아니면 확인 창이 뜬다.
  @State private var pendingUndo: PendingUndo?
  @State private var stopAskingUndo = false
  /// 작품 전체 검색. 처음 열 때 만들고, 패널을 닫아도 문구와 결과는 남긴다(다시 열면 이어서).
  @State private var search: ProjectSearch?
  @State private var showingSearch = false
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
    _selection = State(initialValue: model.episodes.first?.id)
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
      Button("바깥에서 바뀐 내용 쓰기") { model?.autosaver.useDiskVersion(conflict.episodeID) }
    } message: { conflict in
      Text(conflictMessage(conflict))
    }
    .alert("알림", isPresented: isShowingAlert) {
      Button("확인") { alertMessage = nil; model?.errorMessage = nil }
    } message: {
      Text(alertMessage ?? model?.errorMessage ?? "")
    }
    // 판이 보고 있던 회차에서 벗어나면(메뉴·단축키로 회차를 옮기거나 휴지통으로 보냄) 판을 닫는다.
    .onChange(of: selection) {
      if snapshotBrowser?.episodeID != selection { closeSnapshots() }
      // 메뉴·단축키·검색으로 회차를 옮기면 여러 개 고른 것을 그 회차 하나로 줄인다.
      if let selection, !marked.contains(selection) { marked = [selection] }
    }
    // 되돌리기 등으로 보고 있던 회차가 목록에서 사라지면 가까운 회차로 옮긴다.
    .onChange(of: project.episodes.map(\.id)) { old, new in
      guard let current = selection, !new.contains(current) else { return }
      let oldIndex = old.firstIndex(of: current) ?? 0
      selection = new.isEmpty ? nil : new[min(oldIndex, new.count - 1)]
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
        Task {
          await model.autosaver.finish()
          await model.saveCountsNow()
          Self.rescueUnsaved(model)
        }
      }
    }
  }

  /// 사이드바 자리: 회차 목록, 또는 검색 패널(⇧⌘F).
  @ViewBuilder
  private var sidebar: some View {
    if showingSearch, let search {
      SearchPanel(
        search: search, episodes: project.episodes, focusRequest: searchFocusRequest,
        onReveal: { target in
          selection = target.episodeID
          reveal = target
        },
        onClose: { showingSearch = false })
    } else {
      EpisodeList(
        episodes: project.episodes,
        groups: project.groups,
        selection: $selection,
        marked: $marked,
        onRename: model == nil ? nil : { beginRename($0) },
        onTrash: model == nil ? nil : { trashing = $0 },
        onSetGoal: model == nil ? nil : { beginSetGoal($0) },
        onAddAfter: model == nil ? nil : { id in addEpisode(after: id) },
        onMove: model == nil ? nil : { source, destination in
          Task { await model?.moveEpisodes(fromOffsets: source, toOffset: destination, undoManager: undoManager) }
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
    guard let model else { return }
    if search == nil {
      let autosaver = model.autosaver
      search = ProjectSearch(
        store: model.store, episodeIDs: { model.episodes.map(\.id) }, texts: { autosaver.searchTexts() })
    }
    showingSearch = true
    searchFocusRequest += 1
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
        reveal: reveal)
    } else {
      Color.clear
    }
  }

  // MARK: - 회차 명령

  private var actions: WorkspaceActions {
    let index = selection.flatMap { id in project.episodes.firstIndex { $0.id == id } }
    return WorkspaceActions(
      addEpisode: { addEpisode(after: selection) },
      renameSelected: selection.map { id in { beginRename(id) } },
      trashSelected: selection.map { id in { trashing = id } },
      setGoalSelected: selection.map { id in { beginSetGoal(id) } },
      selectPrevious: neighbor(of: index, offset: -1),
      selectNext: neighbor(of: index, offset: 1),
      saveNow: model.map { model in { saveNow(model) } },
      saveWithSnapshot: model.map { model in { saveWithSnapshot(model) } },
      takeSnapshot: selection == nil || snapshotBrowser != nil ? nil : { takeSnapshot() },
      showSnapshots: selection == nil || snapshotBrowser != nil ? nil : { showSnapshots() },
      showSearch: { openSearch() },
      groupMarked: selection == nil ? nil : { beginGrouping(marked.isEmpty ? Set([selection].compactMap { $0 }) : marked) },
      ungroupSelected: selection.flatMap { id in project.episodes.first { $0.id == id }?.group }.map { group in
        { Task { await model?.ungroup(group, undoManager: undoManager) } }
      })
  }

  /// 선택한 회차의 앞(-1)·뒤(+1) 회차로 옮기는 명령. 없으면 nil.
  private func neighbor(of index: Int?, offset: Int) -> (() -> Void)? {
    guard let index, project.episodes.indices.contains(index + offset) else { return nil }
    let id = project.episodes[index + offset].id
    return { selection = id }
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
  private func showSnapshots() {
    guard let model, let id = selection, snapshotBrowser == nil, let editor = model.autosaver.beginPanel() else { return }
    editorHadFocus = editor.hadFocus
    let browser = SnapshotBrowser(store: model.store, episodeID: id, currentText: editor.text)
    snapshotBrowser = browser
    Task { await browser.load() }
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
      guard await browser.restoreSelected(with: model.autosaver), snapshotBrowser === browser else { return }
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

  private func commitRename() {
    guard let model, let id = renaming else { return }
    renaming = nil
    Task { await model.rename(id, to: renameText, undoManager: undoManager) }
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
    if UndoConfirmation.isPaused() {
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

  /// 창을 닫았는데도 저장하지 못한 원고가 남았으면 다른 곳에 내보낼지 묻는다.
  /// 안 내보내면 앱을 끌 때 다시 물을 수 있게 저장기를 붙잡아 둔다(창과 함께 사라지면 원고도 사라진다).
  private static func rescueUnsaved(_ model: ProjectModel) {
    let autosaver = model.autosaver
    guard autosaver.hasUnsavedChanges else { return }
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
    return "이 앱에서도 고친 내용이 있어서 덮어쓰지 않았어요. \(kept)\n어느 쪽을 쓸까요? 고르지 않은 쪽도 스냅샷으로 남아요."
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

/// 사이드바 되돌리기 확인 창(맥 기본 확인 창 + "다시 묻지 않기" 체크).
private struct UndoConfirmationDialog: ViewModifier {
  @Binding var pending: WorkspaceView.PendingUndo?
  @Binding var stopAsking: Bool
  let perform: (WorkspaceView.PendingUndo) -> Void

  func body(content: Content) -> some View {
    content
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
