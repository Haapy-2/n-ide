import NovelCore
import SwiftUI

/// 사이드바의 회차 목록. 한 줄: `번호  제목  글자 수`. 글자 수는 목표 기준(설정)과 같은 값이고, 설정에서 숨길 수 있다.
///
/// 선택 표시는 시스템 것을 쓰지 않고 은은한 회색 배경 하나만 직접 그린다.
/// 시스템 선택은 누르는 순간 파란 강조색으로 칠했다가 편집기로 초점이 넘어가면 회색으로 바뀌어
/// 번쩍이는 것처럼 보이고, 이를 끌 방법이 없다(사용자 요청, DESIGN.md 4장).
struct EpisodeList: View {
  let episodes: [EpisodeMeta]
  @Binding var selection: EpisodeID?
  /// nil이면(미리보기) 메뉴와 드래그가 없다.
  var onRename: ((EpisodeID) -> Void)? = nil
  var onTrash: ((EpisodeID) -> Void)? = nil
  var onSetGoal: ((EpisodeID) -> Void)? = nil
  var onAddAfter: ((EpisodeID) -> Void)? = nil
  var onMove: ((IndexSet, Int) -> Void)? = nil
  /// 사이드바에 초점이 있을 때 ⌘Z(false)·⇧⌘Z(true). 바로 되돌리지 않고 확인 창을 거친다.
  var onUndoCommand: ((_ isRedo: Bool) -> Void)? = nil
  /// 회차를 클릭하면 사이드바가 키보드 초점을 받는다. 초점이 있을 때: ↑↓ 이동, ↩ 이름 변경, ⌘⌫ 휴지통.
  @FocusState private var isFocused: Bool
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.sidebarShowsCharacterCount) private var showsCount = true

  /// 줄 안쪽 왼쪽 여백. "회차" 제목과 회차 번호가 같은 선에서 시작하도록 둘 다 이 값을 쓴다(2026-11-12 사용자 요청).
  private static let contentInset: CGFloat = 8
  var body: some View {
    List {
      // 시스템 구역 제목은 줄과 왼쪽 시작점이 달라 번호와 맞출 수 없어서, 같은 여백을 쓰는 제목 줄을 직접 둔다.
      Text("회차")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.inkMuted)
        .padding(.leading, Self.contentInset)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
      Section {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
          // 클릭 영역 = 회색 선택 칸 전체. 줄 여백을 0으로 하고 여백을 칸 안쪽에 직접 넣어
          // 글자뿐 아니라 칸의 빈 곳을 눌러도 선택되게 한다.
          EpisodeRow(number: index + 1, title: episode.title, count: showsCount ? episode.characterCount?.value(for: basis) : nil)
            .padding(.horizontal, Self.contentInset)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(episode.id == selection ? Color.ink.opacity(0.08) : .clear))
            // 회색 칸 사이의 1pt 틈도 클릭 영역에 넣는다. 틈을 줄 여백(listRowInsets)으로 두면
            // 그곳을 누를 때 아무 반응이 없어 목록이 버벅이는 것처럼 느껴진다.
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            // 두 번 클릭하면 이름 변경. 한 번 클릭 선택은 두 번 클릭 판정을 기다리지 않고 바로 한다.
            .onTapGesture(count: 2) { onRename?(episode.id) }
            .simultaneousGesture(TapGesture().onEnded {
              selection = episode.id
              isFocused = true
            })
            .contextMenu {
              if let onAddAfter, let onRename, let onTrash, let onSetGoal {
                Button("아래에 새 회차") { onAddAfter(episode.id) }
                Button("이름 변경…") { onRename(episode.id) }
                Button("목표 글자 수…") { onSetGoal(episode.id) }
                Divider()
                Button("휴지통으로 이동…") { onTrash(episode.id) }
              }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(episode.id == selection ? [.isButton, .isSelected] : .isButton)
        }
        // 드래그로 순서 바꾸기. 번호는 순서로 매기므로 함께 바뀐다(파일 이름은 그대로).
        .onMove(perform: onMove)
      }
    }
    // 시스템 기본 최소 줄 높이를 없애 줄 사이에 클릭 안 되는 틈이 생기지 않게 한다.
    .environment(\.defaultMinListRowHeight, 0)
    .focusable()
    .focused($isFocused)
    // 초점 표시(파란 테두리)는 그리지 않는다. 선택한 회차의 회색 칸으로 충분하다.
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { move(by: -1) }
    .onKeyPress(.downArrow) { move(by: 1) }
    .onKeyPress(.return) {
      guard let selection, let onRename else { return .ignored }
      onRename(selection)
      return .handled
    }
    // ⌘⌫ 같은 ⌘ 조합은 메뉴가 먼저 가져가서 여기까지 오지 않는다. 그래서 회차 메뉴가 이 값을 보고
    // 사이드바에 초점이 있을 때만 "휴지통으로 이동"의 단축키를 ⌘⌫로 바꿔 처리한다(EpisodeCommands).
    .focusedValue(\.episodeSidebarFocused, isFocused)
    // 편집 메뉴의 실행 취소·다시 실행이 창까지 올라가기 전에 여기서 받는다(확인 창을 띄우려고).
    .onCommand(Selector(("undo:"))) { onUndoCommand?(false) }
    .onCommand(Selector(("redo:"))) { onUndoCommand?(true) }
  }

  private func move(by offset: Int) -> KeyPress.Result {
    guard let selection, let index = episodes.firstIndex(where: { $0.id == selection }),
      episodes.indices.contains(index + offset)
    else { return .ignored }
    self.selection = episodes[index + offset].id
    return .handled
  }
}

private struct EpisodeRow: View {
  let number: Int
  let title: String
  /// 아직 센 적 없는 회차는 nil(비워 둔다).
  let count: Int?

  var body: some View {
    HStack(spacing: 8) {
      Text("\(number)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
        // 왼쪽 정렬: 1이든 100이든 "회차" 제목 아래 같은 선에서 시작하고, 제목도 모두 같은 선에서 시작한다.
        .frame(minWidth: 26, alignment: .leading)
      Text(title.isEmpty ? "제목 없음" : title)
        .font(.system(size: 13))
        .foregroundStyle(title.isEmpty ? Color.inkMuted : Color.primary)
        .lineLimit(1)
      Spacer(minLength: 4)
      if let count {
        Text(count.formatted())
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(Color.inkMuted)
      }
    }
  }
}
