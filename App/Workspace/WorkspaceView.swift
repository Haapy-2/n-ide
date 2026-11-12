import NovelCore
import SwiftUI

/// 작품 하나의 작업 공간: 유리 사이드바(회차 목록) + 불투명 종이 편집 영역.
struct WorkspaceView: View {
  /// nil이면 미리보기·스냅샷용이라 본문을 읽지 않고 목록을 바꿀 수 없다.
  private let model: ProjectModel?
  private let previewProject: ProjectFile?
  /// 사이드바 뒤로 다른 앱·바탕화면이 흐릿하게 비치는 효과. 설정 창에서 끄고 켠다.
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var sidebarSeesThroughWindow = true
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var goalBasis: CharacterCountBasis = .withSpaces
  @State private var selection: EpisodeID?
  @State private var renaming: EpisodeID?
  @State private var renameText = ""
  @State private var trashing: EpisodeID?
  @State private var settingGoal: EpisodeID?
  @State private var goalText = ""
  @State private var alertMessage: String?
  /// 확인을 기다리는 사이드바 되돌리기. nil이 아니면 확인 창이 뜬다.
  @State private var pendingUndo: PendingUndo?
  @State private var stopAskingUndo = false
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
      EpisodeList(
        episodes: project.episodes,
        selection: $selection,
        onRename: model == nil ? nil : { beginRename($0) },
        onTrash: model == nil ? nil : { trashing = $0 },
        onSetGoal: model == nil ? nil : { beginSetGoal($0) },
        onAddAfter: model == nil ? nil : { id in addEpisode(after: id) },
        onMove: model == nil ? nil : { source, destination in
          Task { await model?.moveEpisodes(fromOffsets: source, toOffset: destination, undoManager: undoManager) }
        },
        onUndoCommand: model == nil ? nil : { requestUndo(isRedo: $0) })
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    } detail: {
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        // 제목과 버튼을 편집 영역 쪽 툴바에 붙인다. 사이드바 쪽에 두면 사이드바 폭만큼만 보여서 긴 제목이 잘린다.
        .navigationTitle(project.title)
        .toolbar {
          ToolbarItem {
            Button("새 회차", systemImage: "square.and.pencil") { addEpisode(after: selection) }
              .disabled(model == nil)
          }
          ToolbarItem {
            Button("노트 나란히 보기", systemImage: "sidebar.right") {}
              .disabled(true)
          }
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
    .alert("목표 글자 수", isPresented: isSettingGoal) {
      TextField("글자 수", text: $goalText)
      Button("이 회차만") { commitGoal(alsoForNewEpisodes: false) }
      Button("새 회차에도 쓰기") { commitGoal(alsoForNewEpisodes: true) }
      Button("취소", role: .cancel) { settingGoal = nil }
    } message: {
      Text("\(goalBasis.title) 기준으로 셉니다. 지금 새 회차는 \(project.settings.defaultEpisodeGoal.formatted())자로 시작해요.")
    }
    .modifier(undoConfirmationDialog)
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
        Task {
          await model.autosaver.flush()
          await model.saveCountsNow()
        }
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    if project.episodes.isEmpty {
      EmptyStateView(message: "첫 회차를 추가해 주세요.", buttonTitle: "새 회차", action: model == nil ? nil : { addEpisode(after: nil) })
    } else if let model, let selection {
      EpisodeEditorPane(
        autosaver: model.autosaver, counter: model.counter, episodeID: selection,
        goal: model.episode(selection)?.goal ?? 0, knownCount: model.episode(selection)?.characterCount)
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
      selectNext: neighbor(of: index, offset: 1))
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

// Xcode 캔버스(⌥⌘↩)에서 작업 공간을 바로 볼 수 있다.
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
        // 엔터는 취소가 받는다(2026-11-12 사용자 요청). 되돌리기는 클릭이나 Tab → Space로.
        Button("취소", role: .cancel) { self.pending = nil }
          .keyboardShortcut(.defaultAction)
        Button(pending.isRedo ? "다시 실행" : "되돌리기") { perform(pending) }
      } message: { _ in
        Text("회차 목록이 바뀌기 전으로 돌아가요. 본문은 바뀌지 않아요.")
      }
      .dialogSuppressionToggle("다시 묻지 않기", isSuppressed: $stopAsking)
  }
}
