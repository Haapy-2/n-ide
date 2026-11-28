import SwiftUI

/// Slider + number on the right. The number is monospaced so it doesn't jitter while dragging.
struct NumberSlider: View {
  let title: String
  @Binding var value: Double
  let setting: EditorSetting
  let format: (Double) -> String

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 10) {
        // Even if the stored value is out of range, the slider shows the snapped value.
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
