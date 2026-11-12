import SwiftUI

/// 슬라이더 + 오른쪽 숫자. 숫자는 고정폭이라 끌 때 흔들리지 않는다.
struct NumberSlider: View {
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
