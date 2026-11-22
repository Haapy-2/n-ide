import NovelCore
import SwiftUI

/// 판 오른쪽의 과거↔현재 두 칸 (PLAN 10장 5번, 참고 이미지 11-ref-diff.png).
/// 한 줄(문단)마다 두 칸을 한 줄로 묶어 그려서, 긴 문단이 줄바꿈되어도 두 칸이 같은 높이에 놓인다.
/// 과거 칸은 글자를 골라 복사할 수 있다(결정 11).
struct DiffView: View {
  let diff: TextDiff
  let pastTitle: String
  let presentTitle: String
  @State private var expanded: Set<Int> = []
  private var editorSettings = EditorStyleSettings()

  init(diff: TextDiff, pastTitle: String, presentTitle: String = "현재") {
    self.diff = diff
    self.pastTitle = pastTitle
    self.presentTitle = presentTitle
  }

  var body: some View {
    let style = editorSettings.style
    // 두 칸에 본문을 나란히 넣으므로 본문보다 조금 작게. 글꼴은 본문 글꼴.
    let font = Font.custom(style.fontName, size: max(13, style.fontSize - 2))
    let items = DiffDisplay.items(diff.rows, expanded: expanded)
    let widestNumber = String(max(diff.oldLines.count, diff.newLines.count, 1))
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        header(pastTitle)
        header(presentTitle)
      }
      if !diff.hasChanges || diff.isLineOnly {
        Text(diff.hasChanges ? "글이 길어 줄 단위로만 비교했어요." : "지금과 같아요.")
          .font(.system(size: 12))
          .foregroundStyle(Color.inkMuted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.bottom, 6)
      }
      Rectangle().fill(Color.rule).frame(height: 1)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(items) { item in
            switch item {
            case .row(_, let row):
              DiffRow(row: row, diff: diff, font: font, widestNumber: widestNumber)
            case .folded(let range):
              Button {
                expanded.insert(range.lowerBound)
              } label: {
                Text("같은 줄 \(range.count)개")
                  .font(.system(size: 12))
                  .foregroundStyle(Color.inkMuted)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 6)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .background(Color.ink.opacity(0.03))
            }
          }
        }
        .padding(.vertical, 8)
      }
    }
    // 다른 스냅샷으로 바꾸면 펼친 것을 처음으로.
    .onChange(of: diff) { expanded = [] }
  }

  private func header(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Color.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
  }
}

/// 비교 한 줄: 왼쪽 과거 칸, 오른쪽 현재 칸.
private struct DiffRow: View {
  let row: TextDiff.Row
  let diff: TextDiff
  let font: Font
  let widestNumber: String

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      cell(side: .old)
      Rectangle().fill(Color.rule).frame(width: 1)
      cell(side: .new)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private enum Side { case old, new }

  /// 빗금·막대는 칸 높이를 따라가도록 겹쳐 그린다. 칸 안에 같이 늘어놓으면 글자 기준선 맞춤이 막대 아래 끝을 기준선으로 보고
  /// 글자를 아래로 밀어낸다.
  private func cell(side: Side) -> some View {
    let line = lineIndex(side)
    let hasLine = line != nil
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      // 가장 큰 번호를 숨겨 두고 그 폭에 맞춰, 번호 자릿수가 달라도 본문 시작선이 같다.
      ZStack(alignment: .trailing) {
        Text(widestNumber).hidden()
        Text(line.map { String($0 + 1) } ?? "")
      }
      .font(.system(size: 11).monospacedDigit())
      .foregroundStyle(Color.inkMuted)
      if let line {
        text(line: line, side: side)
          .font(font)
          .foregroundStyle(Color.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .modifier(SelectableIf(isOn: side == .old))
      } else {
        Spacer(minLength: 0)
      }
    }
    .padding(.leading, 12)
    .padding(.trailing, 12)
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(background(side: side, hasLine: hasLine))
    .overlay(alignment: .leading) {
      if isChanged(side, hasLine: hasLine) {
        Group {
          if side == .old { Hatch() } else { Color.diffAddedMark }
        }
        .frame(width: 4)
      }
    }
  }

  private func lineIndex(_ side: Side) -> Int? {
    switch (row, side) {
    case (.same(let o, _), .old), (.removed(let o), .old), (.changed(let o, _, _), .old): o
    case (.same(_, let n), .new), (.added(let n), .new), (.changed(_, let n, _), .new): n
    default: nil
    }
  }

  /// 이 칸이 바뀐 쪽인지(지운 줄의 과거 칸, 넣은 줄의 현재 칸, 고친 줄의 양쪽)
  private func isChanged(_ side: Side, hasLine: Bool) -> Bool {
    hasLine && !row.isSame
  }

  private func background(side: Side, hasLine: Bool) -> Color {
    guard isChanged(side, hasLine: hasLine) else { return .clear }
    return side == .old ? .diffRemoved : .diffAdded
  }

  /// 바뀐 부분만 진하게. 줄 전체가 바뀐 것으로 본 줄은 바탕색만.
  private func text(line: Int, side: Side) -> Text {
    let string = side == .old ? diff.oldLines[line] : diff.newLines[line]
    // 빈 문단도 한 줄 높이를 차지하게(두 칸 줄 맞춤과 줄 번호가 보이도록).
    if string.isEmpty { return Text(" ") }
    guard case .changed(_, _, .ranges(let old, let new)) = row else { return Text(string) }
    let ranges = side == .old ? old : new
    guard !ranges.isEmpty else { return Text(string) }
    var attributed = AttributedString()
    let characters = Array(string)
    var position = 0
    for range in ranges where range.lowerBound >= position && range.upperBound <= characters.count {
      attributed += AttributedString(String(characters[position..<range.lowerBound]))
      var strong = AttributedString(String(characters[range]))
      strong.backgroundColor = side == .old ? .diffRemovedStrong : .diffAddedStrong
      attributed += strong
      position = range.upperBound
    }
    attributed += AttributedString(String(characters[position...]))
    return Text(attributed)
  }
}

/// 지운 줄 왼쪽의 빨간 빗금 막대.
private struct Hatch: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      var y: CGFloat = -size.width
      while y < size.height {
        path.move(to: CGPoint(x: 0, y: y + size.width))
        path.addLine(to: CGPoint(x: size.width, y: y))
        y += 3
      }
      context.stroke(path, with: .color(.error), lineWidth: 1)
    }
  }
}

/// 과거 칸만 글자를 골라 복사할 수 있게.
private struct SelectableIf: ViewModifier {
  let isOn: Bool

  func body(content: Content) -> some View {
    if isOn {
      content.textSelection(.enabled)
    } else {
      content.textSelection(.disabled)
    }
  }
}
