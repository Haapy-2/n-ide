import NovelCore
import SwiftUI

/// 설정 창 "목표" 묶음: 맨 마지막으로 앞에 있던 작품의 새 회차 목표(project.json, 작품별 값).
/// 작품 창이 없으면 안내 한 줄만 보인다(2026-11-12 사용자 요청).
struct ProjectGoalSection: View {
  private var active = ActiveWorkspace.shared
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  /// 입력 중인 값. 엔터를 치거나 칸을 벗어나면 저장한다(한 글자 칠 때마다 저장하지 않게).
  @State private var draft = 0
  @FocusState private var isEditing: Bool

  var body: some View {
    Section {
      if let model = active.model {
        LabeledContent("새 회차 목표") {
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
        LabeledContent("이미 있는 회차") {
          Button("모든 회차에 적용") { applyToAll(model) }
            .disabled(draft <= 0 || model.episodes.allSatisfy { $0.goal == draft })
        }
      } else {
        Text("작품을 열면 바꿀 수 있어요.")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("목표")
    } footer: {
      if let model = active.model {
        Text("「\(model.project.title)」에만 적용돼요. \(basis.title) 기준으로 셉니다. 모든 회차에 적용한 것은 작품 창에서 ⌘Z로 되돌릴 수 있어요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .onChange(of: active.model?.project.settings.defaultEpisodeGoal, initial: true) { _, goal in
      if !isEditing, let goal { draft = goal }
    }
    .onChange(of: isEditing) { _, editing in
      if !editing, let model = active.model { commit(model) }
    }
  }

  private func commit(_ model: ProjectModel) {
    guard draft > 0 else {
      draft = model.project.settings.defaultEpisodeGoal
      return
    }
    model.setDefaultEpisodeGoal(draft, undoManager: ActiveWorkspace.shared.undoManager)
  }

  /// 새 회차 목표와 모든 회차 목표를 함께 바꾼다. 두 되돌리기 기록을 같은 차례에 남겨 ⌘Z 한 번에 함께 되돌아가게.
  private func applyToAll(_ model: ProjectModel) {
    guard draft > 0 else { return }
    let goal = draft
    let undoManager = ActiveWorkspace.shared.undoManager
    Task {
      model.setDefaultEpisodeGoal(goal, undoManager: undoManager)
      await model.setGoalForAllEpisodes(goal, undoManager: undoManager)
    }
  }
}
