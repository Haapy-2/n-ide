import NovelCore
import SwiftUI

/// 판 왼쪽의 스냅샷 목록. 오늘/어제/날짜로 묶은 시각, 오른쪽에 회색 종류 이름, 시각 아래 회색 메모.
/// 줄을 두 번 클릭하면 메모를 고친다(없으면 새로 단다). 엔터나 칸 밖을 누르면 저장, Esc는 그만두기.
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

  /// 엔터와 칸 밖 누르기가 함께 올 수 있어 한 번만 저장한다.
  private func commit(_ id: String) {
    guard editingID == id else { return }
    editingID = nil
    browser.updateMemo(id, to: draft)
  }

  // MARK: - 묶음과 이름

  private struct Group {
    let title: String
    let items: [SnapshotBrowser.Item]
  }

  /// 목록은 최근 것부터라 같은 날끼리 이미 붙어 있다.
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

  /// 초까지 보인다. 같은 분에 여러 번 찍어도 구분되게.
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
    }
  }
}
