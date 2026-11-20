import SwiftUI

/// 설정 창 "커서": 편집기 커서의 두께·높이·색. 색은 라이트/다크를 따로 고른다.
/// 편집기 화면에 넣으면 스크롤이 생겨서 왼쪽 목록에 따로 두었다.
struct CaretSettingsPane: View {
  private var caret = CaretStyleSettings()
  private var editor = EditorStyleSettings()
  @Environment(\.colorScheme) private var appScheme
  /// 색을 고르는 모드. 처음에는 지금 앱 모양을 따른다.
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

  /// 고르고 있는 모드의 색.
  private var colorBinding: Binding<CaretColor> {
    Binding(
      get: { editsDark ? caret.style.darkColor : caret.style.lightColor },
      set: { color in
        if editsDark { caret.darkColorText = color.storageText } else { caret.lightColorText = color.storageText }
      })
  }
}

/// 한 줄짜리 종이 위에 지금 글꼴·크기로 짧은 문장과 커서를 그린다. 고르는 모드(라이트/다크)의 모양으로.
/// 산만하지 않게 깜빡이지 않는다.
private struct CaretPreview: View {
  let editor: EditorStyle
  let caret: CaretStyle
  let dark: Bool

  var body: some View {
    HStack(spacing: 0) {
      Text("비가 그친 골목")
      // 폭 0 칸 가운데에 그려서 글자 사이를 벌리지 않는다(실제 커서처럼 글자 위에 겹친다).
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

/// 두께 입력 칸. 입력을 마치면(엔터·다른 곳 클릭) 1~4pt, 0.5 단위로 맞춘다.
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
    // "기본값으로"처럼 밖에서 바뀌면 칸 글자도 따라간다. 입력 중에는 값이 바뀌지 않아 치던 글자를 덮지 않는다.
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

/// 팔레트 동그라미 다섯 개 + 컬러 피커. 고른 동그라미에는 회색 테두리.
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
