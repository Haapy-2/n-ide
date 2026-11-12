import SwiftUI

/// 설정 창 "일반": 테마, 목표, 되돌리기 확인 창.
struct GeneralSettingsPane: View {
  @AppStorage(AppSettingKey.appTheme) private var theme: AppTheme = .system
  @AppStorage(AppSettingKey.undoConfirmPause) private var undoPause: UndoConfirmPause = .week
  @AppStorage(AppSettingKey.undoConfirmPausedUntil) private var undoPausedUntil: Double = 0

  var body: some View {
    Form {
      Section {
        // 아이콘만 보이고, 마우스를 올리면 이름이 뜬다. 색 없이 시스템 보조 글자색(2026-11-12 사용자 요청, DESIGN 5장 예외).
        Picker("테마", selection: $theme) {
          ForEach(AppTheme.allCases, id: \.self) { theme in
            Image(systemName: theme.symbolName)
              .accessibilityLabel(theme.title)
              .help(theme.title)
          }
        }
        .pickerStyle(.segmented)
      }
      ProjectGoalSection()
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
