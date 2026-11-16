import NovelCore

/// 비교 결과(`TextDiff.rows`)를 화면에 그릴 줄 목록으로 편다. 같은 줄이 길게 이어지면 바뀐 곳 앞뒤 `context`줄만 남기고 접는다.
/// (PLAN 10장 5번: "같은 줄이 길면 앞뒤 3줄만 남기고 '같은 줄 24개'로 접음, 누르면 펼침")
enum DiffDisplay {
  enum Item: Identifiable, Equatable {
    /// `rows`의 위치와 그 줄
    case row(Int, TextDiff.Row)
    /// 접힌 같은 줄들. 범위는 `rows`의 위치
    case folded(Range<Int>)

    var id: Int {
      switch self {
      case .row(let index, _): index
      // 줄 위치와 겹치지 않게 음수로 둔다.
      case .folded(let range): -1 - range.lowerBound
      }
    }
  }

  /// `expanded`: 펼친 접힘의 시작 위치. 바뀐 곳이 하나도 없으면 접지 않는다(스냅샷 글을 그대로 보고 복사할 수 있게).
  static func items(_ rows: [TextDiff.Row], context: Int = 3, expanded: Set<Int> = []) -> [Item] {
    guard rows.contains(where: { !$0.isSame }) else {
      return rows.enumerated().map { .row($0.offset, $0.element) }
    }
    var items: [Item] = []
    var index = 0
    while index < rows.count {
      guard rows[index].isSame else {
        items.append(.row(index, rows[index]))
        index += 1
        continue
      }
      var end = index
      while end < rows.count, rows[end].isSame { end += 1 }
      // 맨 앞 묶음은 뒤쪽만, 맨 끝 묶음은 앞쪽만 남긴다.
      let keepBefore = index == 0 ? 0 : context
      let keepAfter = end == rows.count ? 0 : context
      let first = index + keepBefore
      let last = end - keepAfter
      // 짧은 묶음은 남길 줄끼리 겹친다. 한 줄만 숨기는 것도 "같은 줄 1개" 줄과 높이가 같아서 접지 않는다.
      if last - first >= 2, !expanded.contains(first) {
        let hidden = first..<last
        for i in index..<hidden.lowerBound { items.append(.row(i, rows[i])) }
        items.append(.folded(hidden))
        for i in hidden.upperBound..<end { items.append(.row(i, rows[i])) }
      } else {
        for i in index..<end { items.append(.row(i, rows[i])) }
      }
      index = end
    }
    return items
  }
}

extension TextDiff.Row {
  var isSame: Bool {
    if case .same = self { true } else { false }
  }
}
