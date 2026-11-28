import NovelCore
import SwiftUI

/// The past↔present two columns on the right of the panel (PLAN ch.10 #5, reference 11-ref-diff.png).
/// Each line (paragraph) draws both columns in one row, so long wrapped paragraphs keep both columns at the same height.
/// The past column's text can be selected and copied (decision 11).
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
    // Two columns side by side, so slightly smaller than the body. Font is the body font.
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
    // Switching to another snapshot resets expansions.
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

/// One diff row: past column on the left, present on the right.
extension DiffView {
  /// "그림: 파일 이름" for an image line, nil for text.
  static func imageLabel(_ line: String) -> String? {
    switch ImageLine.parse(line)?.source {
    case .project(let fileName): "그림: \(fileName)"
    case .outside(let path): "그림(작품 밖): \(path)"
    case nil: nil
    }
  }
}

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

  /// Hatching and bars are overlaid to follow the column height. Laid out inside the column, baseline alignment would treat the bar's bottom as the baseline
  /// and push text down.
  private func cell(side: Side) -> some View {
    let line = lineIndex(side)
    let hasLine = line != nil
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      // The largest number is laid out hidden for width, so the text start line stays the same regardless of digit count.
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

  /// Whether this column is the changed side (past column of deleted lines, present column of inserted lines, both for modified lines)
  private func isChanged(_ side: Side, hasLine: Bool) -> Bool {
    hasLine && !row.isSame
  }

  private func background(side: Side, hasLine: Bool) -> Color {
    guard isChanged(side, hasLine: hasLine) else { return .clear }
    return side == .old ? .diffRemoved : .diffAdded
  }

  /// Only the changed part in bold. Lines treated as wholly changed get just the background.
  private func text(line: Int, side: Side) -> Text {
    let string = side == .old ? diff.oldLines[line] : diff.newLines[line]
    // Empty paragraphs still take one line's height (so two-column alignment and line numbers show).
    if string.isEmpty { return Text(" ") }
    // An image line shows what it is, not its path characters (G14). The comparison itself still runs on the real text.
    if let label = DiffView.imageLabel(string) { return Text(label).foregroundColor(.inkMuted) }
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

/// Red hatched bar left of deleted lines.
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

/// Only the past column is selectable for copying.
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
