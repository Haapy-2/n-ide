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
    let isLocked = settings.isLocked(command)
    return VStack(alignment: .trailing, spacing: 4) {
      HStack {
        Text(command.title)
          .foregroundStyle(isLocked ? .secondary : .primary)
        Spacer()
        if command == .saveWithSnapshot {
          // 켜면 이 칸의 키가 풀리고 지금 저장·스냅샷 찍기 칸이 잠긴다. 다른 줄처럼 조작은 오른쪽에 둔다.
          Toggle(command.title, isOn: savesWithSnapshot)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        if settings.isCustomized(command), !isLocked {
          Button("기본값") { update { $0.reset(command) } }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("기본값: \(command.defaultCombo?.displayText ?? "없음")")
        }
        ShortcutRecorder(
          combo: settings.combo(for: command),
          isRecording: recording == command,
          onStart: {
            guard !settings.isLocked(command) else { return }
            notice = nil
            recording = command
          },
          onFinish: { finish($0, for: command) })
        .disabled(isLocked)
        // 칸 글자가 .primary로 칠해져 있어 흐림이 잘 안 보여서 따로 흐리게 한다.
        .opacity(isLocked ? 0.45 : 1)
        .help(isLocked ? lockedHelp(command) : "")
      }
      if command == .saveWithSnapshot {
        Text("켜면 이 키 한 번으로 저장하고 스냅샷도 찍어요. 글이 마지막 스냅샷과 같으면 스냅샷은 건너뛰어요. 켜 있는 동안 지금 저장·스냅샷 찍기 키는 잠겨요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      // 기본값일 때만 회차 메뉴가 사이드바 초점에 따라 ⌘⌫로 바꿔 보여서(EpisodeCommands), 표와 메뉴가 달라 보이지 않게 알린다.
      if command == .trashEpisode, !settings.isCustomized(command) {
        Text("사이드바에서 회차를 고른 채로는 ⌘⌫로도 돼요. 편집기에서 ⌘⌫는 줄 앞까지 지우기예요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let notice, notice.command == command {
        Text(notice.text)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func lockedHelp(_ command: ShortcutCommand) -> String {
    command == .saveWithSnapshot ? "옆 스위치를 켜면 바꿀 수 있어요" : "‘저장하면서 스냅샷 찍기’가 켜져 있어 잠겼어요"
  }

  /// 켜고 끌 때 녹화 중이던 칸과 안내는 그만둔다(잠기는 칸이 녹화 중일 수 있어서).
  private var savesWithSnapshot: Binding<Bool> {
    Binding(get: { settings.savesWithSnapshot }, set: { on in
      recording = nil
      notice = nil
      update { $0.setSavesWithSnapshot(on) }
    })
  }

  private func finish(_ outcome: ShortcutRecorder.Outcome, for command: ShortcutCommand) {
    guard recording == command, !settings.isLocked(command) else { return }
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
      case .usedByLocked(let owner):
        notice = (command, "\(combo.displayText)는 잠긴 ‘\(owner.title)’이(가) 쓰고 있어서 고를 수 없어요.")
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
