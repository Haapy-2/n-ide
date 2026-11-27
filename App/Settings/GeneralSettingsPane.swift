import SwiftUI

/// 설정 창 "일반": 테마, 목표, 스냅샷, 되돌리기 확인 창, 알림.
struct GeneralSettingsPane: View {
  @AppStorage(AppSettingKey.appTheme) private var theme: AppTheme = .system
  @AppStorage(AppSettingKey.undoConfirmPause) private var undoPause: UndoConfirmPause = .week
  @AppStorage(AppSettingKey.undoConfirmPausedUntil) private var undoPausedUntil: Double = 0
  @AppStorage(AppSettingKey.autoSnapshotEnabled) private var autoSnapshot = true
  @AppStorage(AppSettingKey.autoSnapshotMinutes) private var snapshotMinutes = 30
  @AppStorage(AppSettingKey.snapshotRetention) private var snapshotRetention = 50
  @AppStorage(AppSettingKey.toastDuration) private var toastDuration = EditorSetting.toastDuration.defaultValue
  @AppStorage(AppSettingKey.sidebarShowsCharacterCount) private var showsCount = true
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var seesThroughWindow = true

  var body: some View {
    Form {
      Section {
        // 아이콘만 보이고, 마우스를 올리면 이름이 뜬다. 색 없이 시스템 보조 글자색.
        Picker("테마", selection: $theme) {
          ForEach(AppTheme.allCases, id: \.self) { theme in
            Image(systemName: theme.symbolName)
              .accessibilityLabel(theme.title)
              .help(theme.title)
          }
        }
        .pickerStyle(.segmented)
      }
      // 사이드바 설정은 두 개뿐이라 따로 판을 두지 않는다(판 아래가 비어 보였다).
      Section("사이드바") {
        Toggle("글자 수 보이기", isOn: $showsCount)
        Toggle("뒤로 창 비치기", isOn: $seesThroughWindow)
      }
      ProjectGoalSection()
      Section {
        Toggle("자동 스냅샷", isOn: $autoSnapshot)
        Picker("간격", selection: $snapshotMinutes) {
          ForEach(EpisodeSnapshotter.Settings.intervalChoices, id: \.self) { Text("\($0)분") }
        }
        .disabled(!autoSnapshot)
        Picker("보관 개수", selection: $snapshotRetention) {
          ForEach(Array(stride(from: 10, through: 100, by: 10)), id: \.self) { Text("\($0)개") }
        }
      } header: {
        Text("스냅샷")
      } footer: {
        Text("자동 스냅샷은 그사이 고친 회차만 찍어요. 회차를 떠날 때는 늘 찍어요. 보관 개수를 넘으면 자동·떠날 때·이름 변경 스냅샷 중 오래된 것부터 지우고, 직접 찍은 것과 메모를 단 것은 지우지 않아요(이름 변경은 지키기로 한 것만).")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Section {
        Picker("확인 창 다시 띄우기", selection: $undoPause) {
          ForEach(UndoConfirmPause.allCases, id: \.self) { Text($0.title) }
        }
        if undoPausedUntil > Date.now.timeIntervalSince1970 {
          LabeledContent(pausedText) {
            Button("지금부터 다시 묻기") { UndoConfirmation.resume() }
          }
        }
      } header: {
        Text("되돌리기")
      } footer: {
        Text("사이드바에서 ⌘Z로 회차 작업을 되돌릴 때 묻는 창이에요. 그 창에서 \"다시 묻지 않기\"를 고르면 위 기간 동안 묻지 않아요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Section {
        NumberSlider(title: "유지 시간", value: $toastDuration, setting: .toastDuration) { String(format: "%.1f초", $0) }
      } header: {
        Text("알림")
      } footer: {
        Text("저장·스냅샷 알림이 화면에 머무는 시간이에요. 마우스를 올려 두면 기다려요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  /// 예: "5월 19일까지 묻지 않음", 계속이면 "묻지 않는 중"
  private var pausedText: String {
    let until = Date(timeIntervalSince1970: undoPausedUntil)
    guard until < .distantFuture.addingTimeInterval(-86_400) else { return "묻지 않는 중" }
    return "\(until.formatted(.dateTime.month().day()))까지 묻지 않음"
  }
}
