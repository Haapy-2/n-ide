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
        NumberSlider(title: "글자 수 갱신", value: $countInterval, setting: .characterCountInterval) {
          $0 == 0 ? "실시간" : String(format: "%.1f초", $0)
        }
      }
      Section("화면") {
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
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .fixedSize(horizontal: false, vertical: true)
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
