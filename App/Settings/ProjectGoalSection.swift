import NovelCore
import SwiftUI

/// "Goal" group in Settings "General": the episode goal of the most recently front project (project.json, per project) and the goal basis (app-wide).
/// Changing it applies to all existing episodes and future ones.
/// To differ for one episode, use the episode menu's "목표 글자 수…". Without a project window only a one-line hint shows.
struct ProjectGoalSection: View {
  private var active = ActiveWorkspace.shared
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  /// Value being typed. Saved on Return or leaving the field (not per keystroke).
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
      // The basis is app-wide, so it can change without a project.
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
    // Opening Settings makes macOS put the cursor in the first field; remove it right away so the goal field doesn't enter editing by itself.
    // Must remove it on the turn after the window appears and macOS sets the cursor, so wait a little.
    .task {
      try? await Task.sleep(for: .milliseconds(50))
      isEditing = false
    }
    // If another project window comes to the front while typing, switch to that project's value and end editing.
    // Otherwise leaving the field would apply the value typed for project A to every episode goal of project B.
    .onChange(of: active.model.map(ObjectIdentifier.init)) {
      guard isEditing else { return }
      draft = active.model?.project.settings.defaultEpisodeGoal ?? 0
      isEditing = false
    }
    .onChange(of: isEditing) { _, editing in
      if !editing, let model = active.model { commit(model) }
    }
  }

  /// Change the new-episode goal and all episode goals together. Both undo records are registered in the same turn so one ⌘Z reverts both.
  private func commit(_ model: ProjectModel) {
    guard draft > 0 else {
      draft = model.project.settings.defaultEpisodeGoal
      return
    }
    // Do nothing if the value is unchanged. Merely clicking into and out of the field must not overwrite per-episode goals.
    guard draft != model.project.settings.defaultEpisodeGoal else { return }
    let goal = draft
    let undoManager = ActiveWorkspace.shared.undoManager
    Task {
      model.setDefaultEpisodeGoal(goal, undoManager: undoManager)
      await model.setGoalForAllEpisodes(goal, undoManager: undoManager)
    }
  }
}
