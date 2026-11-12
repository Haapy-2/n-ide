import NovelCore
import SwiftUI

/// 설정 창(⌘,) (DESIGN.md 4장 "설정 창"). 앱 전체 설정이라 UserDefaults에 저장되고, 어느 작품을 열어도 같다.
/// 값을 바꾸면 열려 있는 편집 영역·상태 줄·사이드바에 바로 반영된다.
struct SettingsView: View {
  private var editor = EditorStyleSettings()
  @AppStorage(AppSettingKey.characterCountDisplay) private var display: CharacterCountDisplay = .both
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.goalProgressStyle) private var progressStyle: GoalProgressStyle = .ring
  @AppStorage(AppSettingKey.sidebarSeesThroughWindow) private var sidebarSeesThroughWindow = true
  @AppStorage(AppSettingKey.characterCountInterval) private var countInterval = EditorSetting.characterCountInterval.defaultValue
  @AppStorage(AppSettingKey.statusBarHidesWhileTyping) private var hidesWhileTyping = false
  @AppStorage(AppSettingKey.statusBarHidesWhenIdle) private var hidesWhenIdle = true
  @AppStorage(AppSettingKey.sidebarShowsCharacterCount) private var sidebarShowsCount = true
  @AppStorage(AppSettingKey.appTheme) private var theme: AppTheme = .system
  @AppStorage(AppSettingKey.undoConfirmPause) private var undoPause: UndoConfirmPause = .week
  @AppStorage(AppSettingKey.undoConfirmPausedUntil) private var undoPausedUntil: Double = 0

  var body: some View {
    Form {
      Section("편집기") {
        EditorPreview(style: editor.style)
          .clipShape(.rect(cornerRadius: 6))
        Picker("본문 글꼴", selection: editor.$font) {
          ForEach(BodyFont.allCases, id: \.self) { Text($0.title) }
        }
        NumberSlider(title: "글자 크기", value: editor.$fontSize, setting: .fontSize) { "\(Int($0))pt" }
        NumberSlider(title: "줄 간격", value: editor.$lineSpacing, setting: .lineSpacing) { String(format: "%.2f배", $0) }
        NumberSlider(title: "문단 간격", value: editor.$paragraphSpacing, setting: .paragraphSpacing) { String(format: "%.1f줄", $0) }
        NumberSlider(title: "본문 폭", value: editor.$lineWidthInCharacters, setting: .lineWidthInCharacters) { "\(Int($0))자" }
      }
      Section("글자 수") {
        Picker("표시", selection: $display) {
          ForEach(CharacterCountDisplay.allCases, id: \.self) { Text($0.title) }
        }
        Picker("목표 기준", selection: $basis) {
          ForEach(CharacterCountBasis.allCases, id: \.self) { Text($0.title) }
        }
        Picker("진행률 모양", selection: $progressStyle) {
          ForEach(GoalProgressStyle.allCases, id: \.self) { Text($0.title) }
        }
        Toggle("사이드바에 글자 수 보이기", isOn: $sidebarShowsCount)
        NumberSlider(title: "글자 수 갱신", value: $countInterval, setting: .characterCountInterval) {
          $0 == 0 ? "실시간" : String(format: "%.1f초", $0)
        }
      }
      ProjectGoalSection()
      Section("화면") {
        // 아이콘만 보이고, 마우스를 올리면 이름이 뜬다. 색 없이 시스템 보조 글자색(2026-11-12 사용자 요청, DESIGN 5장 예외).
        Picker("테마", selection: $theme) {
          ForEach(AppTheme.allCases, id: \.self) { theme in
            Image(systemName: theme.symbolName)
              .accessibilityLabel(theme.title)
              .help(theme.title)
          }
        }
        .pickerStyle(.segmented)
        Picker("타이핑 중 상태 줄", selection: $hidesWhileTyping) {
          Text("계속 보이기").tag(false)
          Text("숨기기").tag(true)
        }
        Picker("쉬고 있을 때 상태 줄", selection: $hidesWhenIdle) {
          Text("계속 보이기").tag(false)
          Text("10초 뒤 숨기기").tag(true)
        }
        Toggle("사이드바 뒤로 창 비치기", isOn: $sidebarSeesThroughWindow)
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
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
  }
}

extension SettingsView {
  /// 예: "5월 19일까지 묻지 않음", 계속이면 "묻지 않음"
  fileprivate var pausedText: String {
    let until = Date(timeIntervalSince1970: undoPausedUntil)
    guard until < .distantFuture.addingTimeInterval(-86_400) else { return "묻지 않는 중" }
    return "\(until.formatted(.dateTime.month().day()))까지 묻지 않음"
  }
}

/// 슬라이더 + 오른쪽 숫자. 숫자는 고정폭이라 끌 때 흔들리지 않는다.
private struct NumberSlider: View {
  let title: String
  @Binding var value: Double
  let setting: EditorSetting
  let format: (Double) -> String

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        // 저장된 값이 범위 밖이어도 슬라이더에는 맞춘 값을 보여준다.
        Slider(value: Binding(get: { setting.clamped(value) }, set: { value = setting.clamped($0) }),
               in: setting.range, step: setting.step)
        Text(format(setting.clamped(value)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 48, alignment: .trailing)
      }
      .frame(width: 240)
    }
  }
}
