import NovelCore
import SwiftUI

/// 설정 창 "일반"의 "목표" 묶음: 맨 마지막으로 앞에 있던 작품의 회차 목표(project.json, 작품별 값)와 목표 기준(앱 전체).
/// 바꾸면 이미 있는 모든 회차와 앞으로 만들 회차에 함께 적용된다(2026-11-12 사용자 요청: 기본으로 모든 회차).
/// 회차 하나만 다르게 하려면 회차 메뉴의 "목표 글자 수…"를 쓴다. 작품 창이 없으면 안내 한 줄만 보인다.
struct ProjectGoalSection: View {
  private var active = ActiveWorkspace.shared
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  /// 입력 중인 값. 엔터를 치거나 칸을 벗어나면 저장한다(한 글자 칠 때마다 저장하지 않게).
  @State private var draft = 0
  @FocusState private var isEditing: Bool

  var body: some View {
    Section {
      if let model = active.model {
        LabeledContent("회차 목표") {
          HStack(spacing: 4) {
            TextField("", value: $draft, format: .number)
              .labelsHidden()
              .multilineTextAlignment(.trailing)
              .frame(width: 80)
              .focused($isEditing)
              .onSubmit { commit(model) }
            Text("자")
          }
        }
      } else {
        Text("작품을 열면 바꿀 수 있어요.")
          .foregroundStyle(.secondary)
      }
      // 기준은 앱 전체 값이라 작품이 없어도 바꿀 수 있다.
      Picker("목표 기준", selection: $basis) {
        ForEach(CharacterCountBasis.allCases, id: \.self) { Text($0.title) }
      }
    } header: {
      Text("목표")
    } footer: {
      if let model = active.model {
        Text("「\(model.project.title)」의 모든 회차와 새 회차에 적용돼요. \(basis.title) 기준으로 셉니다. 작품 창에서 ⌘Z로 되돌릴 수 있고, 회차 하나만 바꾸려면 회차 메뉴의 \"목표 글자 수…\"를 쓰세요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .onChange(of: active.model?.project.settings.defaultEpisodeGoal, initial: true) { _, goal in
      if !isEditing, let goal { draft = goal }
    }
    // 설정 창을 열면 맥이 첫 입력 칸에 커서를 넣는데, 목표 칸이 저절로 입력 상태가 되지 않게 바로 뺀다(2026-11-12 사용자 요청).
    // 창이 뜨고 맥이 커서를 넣은 다음 차례에 빼야 해서 조금 기다린다.
    .task {
      try? await Task.sleep(for: .milliseconds(50))
      isEditing = false
    }
    .onChange(of: isEditing) { _, editing in
      if !editing, let model = active.model { commit(model) }
    }
  }

  /// 새 회차 목표와 모든 회차 목표를 함께 바꾼다. 두 되돌리기 기록을 같은 차례에 남겨 ⌘Z 한 번에 함께 되돌아가게.
  private func commit(_ model: ProjectModel) {
    guard draft > 0 else {
      draft = model.project.settings.defaultEpisodeGoal
      return
    }
    // 값이 그대로면 아무것도 하지 않는다. 칸을 눌렀다 나가기만 해도 회차별로 따로 정한 목표가 덮이면 안 되니까.
    guard draft != model.project.settings.defaultEpisodeGoal else { return }
    let goal = draft
    let undoManager = ActiveWorkspace.shared.undoManager
    Task {
      model.setDefaultEpisodeGoal(goal, undoManager: undoManager)
      await model.setGoalForAllEpisodes(goal, undoManager: undoManager)
    }
  }
}
