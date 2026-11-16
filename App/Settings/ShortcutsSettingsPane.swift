import SwiftUI

/// 설정 창 "단축키": 메뉴 명령을 분류별로 보여 주고 단축키를 바꾼다(PLAN.md 12장).
struct ShortcutsSettingsPane: View {
  /// 지금 키를 기다리는 명령. 한 번에 하나만.
  @State private var recording: ShortcutCommand?
  /// 고를 수 없던 조합의 안내. 해당 줄 아래에 보인다.
  @State private var notice: (command: ShortcutCommand, text: String)?
  /// 다른 명령이 쓰던 조합을 가져올지 묻는 중
  @State private var pendingTake: PendingTake?

  private struct PendingTake {
    let combo: KeyCombo
    let command: ShortcutCommand
    let owner: ShortcutCommand
  }

  private var settings: ShortcutSettings { ShortcutStore.shared.settings }

  var body: some View {
    Form {
      ForEach(ShortcutCommand.Category.allCases, id: \.self) { category in
        Section(category.title) {
          ForEach(category.commands) { row($0) }
        }
      }
      Section {
        Button("모두 기본값으로") { update { $0.resetAll() } }
          .disabled(!settings.hasCustomizations)
      } footer: {
        Text("칸을 누르고 원하는 키를 함께 누르세요. ⌘가 들어가야 해요. Esc는 그만두기, ⌫는 단축키 없애기.")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .alert(takeTitle, isPresented: isAskingTake, presenting: pendingTake) { pending in
      Button("바꾸기") {
        update { $0.take(pending.combo, for: pending.command, from: pending.owner) }
        pendingTake = nil
      }
      Button("취소", role: .cancel) { pendingTake = nil }
    } message: { pending in
      Text("바꾸면 ‘\(pending.owner.title)’에는 단축키가 없어져요.")
    }
  }

  private func row(_ command: ShortcutCommand) -> some View {
    VStack(alignment: .trailing, spacing: 4) {
      HStack {
        Text(command.title)
        Spacer()
        if settings.isCustomized(command) {
          Button("기본값") { update { $0.reset(command) } }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("기본값: \(command.defaultCombo?.displayText ?? "없음")")
        }
        ShortcutRecorder(
          combo: settings.combo(for: command),
          isRecording: recording == command,
          onStart: {
            notice = nil
            recording = command
          },
          onFinish: { finish($0, for: command) })
      }
      if let notice, notice.command == command {
        Text(notice.text)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func finish(_ outcome: ShortcutRecorder.Outcome, for command: ShortcutCommand) {
    guard recording == command else { return }
    recording = nil
    switch outcome {
    case .cancelled:
      break
    case .cleared:
      update { $0.set(nil, for: command) }
    case .recorded(let combo):
      switch settings.problem(with: combo, for: command) {
      case nil:
        update { $0.set(combo, for: command) }
      case .needsCommand:
        notice = (command, "⌘를 함께 눌러 주세요. ⌘ 없는 조합은 글을 쓸 때 막혀요.")
      case .reserved(let owner):
        notice = (command, "\(combo.displayText)는 \(owner)에 쓰여서 고를 수 없어요.")
      case .usedBy(let owner):
        pendingTake = PendingTake(combo: combo, command: command, owner: owner)
      }
    }
  }

  private func update(_ change: (inout ShortcutSettings) -> Void) {
    ShortcutStore.shared.update(change)
  }

  private var takeTitle: String {
    guard let pending = pendingTake else { return "" }
    return "\(pending.combo.displayText)는 ‘\(pending.owner.title)’이(가) 쓰고 있어요"
  }

  private var isAskingTake: Binding<Bool> {
    Binding(get: { pendingTake != nil }, set: { if !$0 { pendingTake = nil } })
  }
}
