import SwiftUI

/// 설정 창 "편집기": 본문 모양과 아래 상태 줄.
struct EditorSettingsPane: View {
  private var editor = EditorStyleSettings()
  @AppStorage(AppSettingKey.characterCountDisplay) private var display: CharacterCountDisplay = .both
  @AppStorage(AppSettingKey.goalProgressStyle) private var progressStyle: GoalProgressStyle = .ring
  @AppStorage(AppSettingKey.characterCountInterval) private var countInterval = EditorSetting.characterCountInterval.defaultValue
  @AppStorage(AppSettingKey.statusBarHidesWhileTyping) private var hidesWhileTyping = false
  @AppStorage(AppSettingKey.statusBarHidesWhenIdle) private var hidesWhenIdle = true
  @AppStorage(AppSettingKey.showsLineNumbers) private var showsLineNumbers = false
  @AppStorage(AppSettingKey.multiCursorEnabled) private var multiCursorEnabled = true

  var body: some View {
    Form {
      Section("본문") {
        EditorPreview(style: editor.style)
          .clipShape(.rect(cornerRadius: 6))
        Picker("글꼴", selection: editor.$font) {
          ForEach(BodyFont.allCases, id: \.self) { Text($0.title) }
        }
        NumberSlider(title: "글자 크기", value: editor.$fontSize, setting: .fontSize) { "\(Int($0))pt" }
        NumberSlider(title: "줄 간격", value: editor.$lineSpacing, setting: .lineSpacing) { String(format: "%.2f배", $0) }
        NumberSlider(title: "문단 간격", value: editor.$paragraphSpacing, setting: .paragraphSpacing) { String(format: "%.1f줄", $0) }
        NumberSlider(title: "본문 폭", value: editor.$lineWidthInCharacters, setting: .lineWidthInCharacters) { "\(Int($0))자" }
        Toggle("줄 번호 보이기", isOn: $showsLineNumbers)
        Toggle(isOn: $multiCursorEnabled) {
          Text("같은 말 여러 커서")
          Text(multiCursorDescription)
        }
      }
      Section("상태 줄") {
        Picker("글자 수", selection: $display) {
          ForEach(CharacterCountDisplay.allCases, id: \.self) { Text($0.title) }
        }
        Picker("진행률", selection: $progressStyle) {
          ForEach(GoalProgressStyle.allCases, id: \.self) { Text($0.title) }
        }
        NumberSlider(title: "갱신 간격", value: $countInterval, setting: .characterCountInterval) {
          $0 == 0 ? "실시간" : String(format: "%.1f초", $0)
        }
        Picker("타이핑 중", selection: $hidesWhileTyping) {
          Text("계속 보이기").tag(false)
          Text("숨기기").tag(true)
        }
        Picker("쉬고 있을 때", selection: $hidesWhenIdle) {
          Text("계속 보이기").tag(false)
          Text("10초 뒤 숨기기").tag(true)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// 단축키는 설정에서 바꿀 수 있어 제목에 넣지 않고 지금 키를 여기 보인다.
  private var multiCursorDescription: String {
    let sentence = "같은 말을 하나씩 더 골라 한꺼번에 고쳐요"
    guard let combo = ShortcutStore.shared.settings.combo(for: .selectNextOccurrence) else { return sentence }
    return "\(sentence) (\(combo.displayText))"
  }
}
