import SwiftUI

/// Settings "Caret": editor caret width, height and color. Colors are chosen separately for light and dark.
/// Putting it in the editor pane would require scrolling, so it has its own entry in the left list.
struct CaretSettingsPane: View {
  private var caret = CaretStyleSettings()
  private var editor = EditorStyleSettings()
  @Environment(\.colorScheme) private var appScheme
  /// Appearance whose color is being chosen. Initially follows the current app appearance.
  @State private var pickedDark: Bool?

  private var editsDark: Bool { pickedDark ?? (appScheme == .dark) }

  var body: some View {
    let style = caret.style
    Form {
      Section {
        CaretPreview(editor: editor.style, caret: style, dark: editsDark)
      }
      Section {
        LabeledContent("두께") {
          CaretWidthField(value: caret.$width)
        }
        NumberSlider(title: "높이", value: caret.$heightRatio, setting: .caretHeightRatio) { String(format: "%.2f배", $0) }
      }
      Section {
        Picker("모드", selection: Binding(get: { editsDark }, set: { pickedDark = $0 })) {
          Text("라이트").tag(false)
          Text("다크").tag(true)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        LabeledContent("색") {
          CaretColorRow(selection: colorBinding)
            .environment(\.colorScheme, editsDark ? .dark : .light)
        }
      } footer: {
        HStack {
          Spacer()
          Button("기본값으로") { caret.reset() }
            .disabled(style == CaretStyle())
        }
      }
    }
    .formStyle(.grouped)
  }

  /// Color for the appearance being chosen.
  private var colorBinding: Binding<CaretColor> {
    Binding(
      get: { editsDark ? caret.style.darkColor : caret.style.lightColor },
      set: { color in
        if editsDark { caret.darkColorText = color.storageText } else { caret.lightColorText = color.storageText }
      })
  }
}

/// Draws a short sentence and the caret on a one-line paper in the current font and size, in the chosen appearance (light/dark).
/// Doesn't blink, to avoid distraction.
private struct CaretPreview: View {
  let editor: EditorStyle
  let caret: CaretStyle
  let dark: Bool

  var body: some View {
    HStack(spacing: 0) {
      Text("비가 그친 골목")
      // Drawn centered in a zero-width box so it doesn't widen the character gap (overlaps glyphs like a real caret).
      Rectangle()
        .fill((dark ? caret.darkColor : caret.lightColor).color)
        .frame(width: caret.width, height: (editor.fontSize * caret.heightRatio).rounded())
        .frame(width: 0)
      Text("에는 아직")
    }
    .font(Font(editor.font as CTFont))
    .foregroundStyle(Color.ink)
    .lineLimit(1)
    .fixedSize()
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.paper)
    .clipShape(.rect(cornerRadius: 6))
    .environment(\.colorScheme, dark ? .dark : .light)
    .accessibilityLabel("커서 미리 보기")
  }
}

/// Width input field. On commit (Return, click elsewhere) snapped to 1–4 pt in 0.5 steps.
private struct CaretWidthField: View {
  @Binding var value: Double
  @State private var text = ""
  @FocusState private var focused: Bool

  private let setting = EditorSetting.caretWidth

  var body: some View {
    HStack(spacing: 6) {
      TextField("두께", text: $text)
        .labelsHidden()
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 48)
        .focused($focused)
        .onSubmit(commit)
      Text("pt")
        .foregroundStyle(.secondary)
    }
    .onAppear { text = Self.format(setting.clamped(value)) }
    .onChange(of: focused) { if !focused { commit() } }
    // When changed from outside (like "restore defaults") the field text follows. The value doesn't change while typing, so typed text isn't overwritten.
    .onChange(of: value) { text = Self.format(setting.clamped(value)) }
  }

  private func commit() {
    let typed = Double(text.trimmingCharacters(in: .whitespaces)) ?? value
    value = setting.clamped(typed)
    text = Self.format(value)
  }

  /// 2 → "2", 2.5 → "2.5"
  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}

/// Five palette circles + color picker. The chosen circle gets a gray ring.
private struct CaretColorRow: View {
  @Binding var selection: CaretColor

  var body: some View {
    HStack(spacing: 6) {
      ForEach(CaretPalette.allCases, id: \.self) { palette in
        let isSelected = selection == .palette(palette)
        Circle()
          .fill(palette.color)
          .frame(width: 18, height: 18)
          .padding(3)
          .overlay(Circle().strokeBorder(Color.secondary, lineWidth: 1.5).opacity(isSelected ? 1 : 0))
          .contentShape(Circle())
          .onTapGesture { selection = .palette(palette) }
          .help(palette.title)
          .accessibilityLabel(palette.title)
          .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      }
      ColorPicker(
        "다른 색",
        selection: Binding(get: { selection.color }, set: { if let picked = CaretColor(picked: $0) { selection = picked } }),
        supportsOpacity: false)
        .labelsHidden()
        .help("다른 색")
    }
  }
}
