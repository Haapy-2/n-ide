import NovelCore

/// Flatten the diff (`TextDiff.rows`) into display rows. Long runs of unchanged lines are folded, keeping `context` lines around changes.
/// (PLAN ch.10 #5: "long unchanged runs keep 3 lines before/after and fold into '같은 줄 24개', expand on click")
enum DiffDisplay {
  enum Item: Identifiable, Equatable {
    /// Position in `rows` and that row
    case row(Int, TextDiff.Row)
    /// Folded unchanged lines. Range is positions in `rows`
    case folded(Range<Int>)

    var id: Int {
      switch self {
      case .row(let index, _): index
      // Negative so it can't collide with row positions.
      case .folded(let range): -1 - range.lowerBound
      }
    }
  }

  /// `expanded`: start positions of expanded folds. With no changes at all, nothing is folded (so snapshot text can be viewed and copied as is).
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
      // The first run keeps only its tail, the last only its head.
      let keepBefore = index == 0 ? 0 : context
      let keepAfter = end == rows.count ? 0 : context
      let first = index + keepBefore
      let last = end - keepAfter
      // Short runs overlap their kept lines. Hiding just one line is the same height as a "같은 줄 1개" row, so it isn't folded.
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
