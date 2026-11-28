import NovelCore
import SwiftUI

/// Snapshot list on the left of the panel. Times grouped by today/yesterday/date, gray kind name on the right, gray memo under the time.
/// Double-click a row to edit its memo (or add one). Return or clicking outside saves, Esc cancels.
struct SnapshotListView: View {
  let browser: SnapshotBrowser
  @Binding var editingID: String?
  @State private var draft = ""
  @FocusState private var memoFocused: Bool

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        ForEach(groups, id: \.title) { group in
          Text(group.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.inkMuted)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 2)
          ForEach(group.items) { item in row(item) }
        }
      }
      .padding(8)
    }
    .overlay {
      if browser.items?.isEmpty == true {
        Text(emptyMessage)
          .font(.system(size: 12))
          .foregroundStyle(Color.inkMuted)
          .multilineTextAlignment(.center)
      }
    }
  }

  private var emptyMessage: String {
    guard let combo = ShortcutStore.shared.settings.combo(for: .takeSnapshot) else {
      return "아직 스냅샷이 없어요.\n파일 → 스냅샷 찍기로 찍을 수 있어요."
    }
    return "아직 스냅샷이 없어요.\n\(combo.displayText)로 찍을 수 있어요."
  }

  private func row(_ item: SnapshotBrowser.Item) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline) {
        Text(Self.time(item.snapshot.date))
          .font(.system(size: 13).monospacedDigit())
          .foregroundStyle(Color.ink)
        Spacer(minLength: 8)
        if item.snapshot.kind == .rename, item.isKept {
          Image(systemName: "pin.fill")
            .font(.system(size: 9))
            .foregroundStyle(Color.inkMuted)
            .accessibilityLabel("지킴")
        }
        Text(Self.kindName(item.snapshot.kind))
          .font(.system(size: 11))
          .foregroundStyle(Color.inkMuted)
      }
      if editingID == item.id {
        TextField("메모", text: $draft)
          .textFieldStyle(.plain)
          .font(.system(size: 12))
          .foregroundStyle(Color.ink)
          .focused($memoFocused)
          .onSubmit { commit(item.id) }
          .onExitCommand { editingID = nil }
          .onChange(of: memoFocused) { if !memoFocused { commit(item.id) } }
      } else if let memo = item.memo {
        Text(memo)
          .font(.system(size: 12))
          .foregroundStyle(Color.inkMuted)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .rowHighlight(isSelected: item.id == browser.selectedID)
    .onTapGesture(count: 2) { beginEditing(item) }
    .simultaneousGesture(TapGesture().onEnded { browser.select(item.id) })
    .accessibilityAddTraits(item.id == browser.selectedID ? [.isButton, .isSelected] : .isButton)
  }

  private func beginEditing(_ item: SnapshotBrowser.Item) {
    draft = item.memo ?? ""
    editingID = item.id
    memoFocused = true
  }

  /// Return and click-outside may both arrive, so save only once.
  private func commit(_ id: String) {
    guard editingID == id else { return }
    editingID = nil
    browser.updateMemo(id, to: draft)
  }

  // MARK: - Grouping and names

  private struct Group {
    let title: String
    let items: [SnapshotBrowser.Item]
  }

  /// The list is newest first, so same-day entries are already adjacent.
  private var groups: [Group] {
    let calendar = Calendar.current
    var result: [Group] = []
    for item in browser.items ?? [] {
      let title = Self.dayTitle(item.snapshot.date, calendar: calendar)
      if result.last?.title == title {
        result[result.count - 1] = Group(title: title, items: result[result.count - 1].items + [item])
      } else {
        result.append(Group(title: title, items: [item]))
      }
    }
    return result
  }

  static func dayTitle(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "오늘" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
      return "어제"
    }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return date.formatted(sameYear ? .dateTime.month().day() : .dateTime.year().month().day())
  }

  /// Shown down to seconds, to distinguish several taken in the same minute.
  static func time(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
  }

  static func kindName(_ kind: SnapshotKind) -> String {
    switch kind {
    case .manual: "직접"
    case .auto: "자동"
    case .leave: "떠날 때"
    case .restore: "복원 전"
    case .conflict: "충돌"
    case .external: "바깥"
    case .replace: "바꾸기 전"
    case .replaced: "바꾼 뒤"
    case .revert: "되돌리기 전"
    case .rename: "이름 변경"
    case .multiCursor: "여러 커서 전"
    }
  }
}
