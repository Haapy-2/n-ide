import NovelCore
import SwiftUI

/// 사이드바의 회차 목록. 한 줄: `번호  제목  글자 수`. 글자 수는 목표 기준(설정)과 같은 값이고, 설정에서 숨길 수 있다.
///
/// 선택 표시는 시스템 것을 쓰지 않고 은은한 회색 배경 하나만 직접 그린다.
/// 시스템 선택은 누르는 순간 파란 강조색으로 칠했다가 편집기로 초점이 넘어가면 회색으로 바뀌어
/// 번쩍이는 것처럼 보이고, 이를 끌 방법이 없다.
struct EpisodeList: View {
  let episodes: [EpisodeMeta]
  /// 회차 묶음 이름(PLAN 8장 B안). 어느 회차가 어느 묶음인지는 회차의 `group`.
  var groups: [EpisodeGroup] = []
  @Binding var selection: EpisodeID?
  /// 여러 개 고른 회차(⌘클릭·⇧클릭). 묶기에 쓴다. 편집기는 `selection` 하나만 연다.
  @Binding var marked: Set<EpisodeID>
  /// 줄 안쪽 왼쪽 여백. "회차" 제목·번호·제목이 모두 이 값을 써서 창 닫기 버튼과 같은 선에서 시작한다.
  /// 실행 중에 재며(nil이면 아직 안 잼), 작업 공간이 들고 있다: 목록이 검색 패널과 바뀔 때마다 새로 재면
  /// 잰 값이 올 때까지 한 번 기본값으로 그려져 글자가 옆으로 튄다.
  @Binding var measuredInset: CGFloat?
  /// nil이면(미리보기) 메뉴와 드래그가 없다.
  var onRename: ((EpisodeID) -> Void)? = nil
  /// 여러 개 고른 회차 위의 우클릭 `N개 회차 이름 변경…`
  var onBatchRename: ((Set<EpisodeID>) -> Void)? = nil
  var onTrash: ((EpisodeID) -> Void)? = nil
  var onSetGoal: ((EpisodeID) -> Void)? = nil
  var onAddAfter: ((EpisodeID) -> Void)? = nil
  /// 드래그로 옮기기: 보이는 줄 번호(묶음 제목 줄 포함, `EpisodeGrouping.drop`)
  var onMove: ((IndexSet, Int) -> Void)? = nil
  /// 묶기(이름을 묻는 창을 띄운다), 묶음 풀기, 묶음 이름 변경, 이미 있는 묶음에 넣기
  var onGroup: ((Set<EpisodeID>) -> Void)? = nil
  var onUngroup: ((GroupID) -> Void)? = nil
  var onRenameGroup: ((GroupID) -> Void)? = nil
  var onAddToGroup: ((Set<EpisodeID>, GroupID) -> Void)? = nil
  /// 사이드바에 초점이 있을 때 ⌘Z(false)·⇧⌘Z(true). 바로 되돌리지 않고 확인 창을 거친다.
  var onUndoCommand: ((_ isRedo: Bool) -> Void)? = nil
  /// 회차의 글자 수 칸. nil이면(미리보기) 회차 정보에 든 값을 보여준다.
  var countBox: ((EpisodeID) -> EpisodeCountBox)? = nil
  /// 회차를 클릭하면 사이드바가 키보드 초점을 받는다. 초점이 있을 때: ↑↓ 이동, ↩ 이름 변경, ⌘⌫ 휴지통.
  @FocusState private var isFocused: Bool
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.sidebarShowsCharacterCount) private var showsCount = true
  @AppStorage(AppSettingKey.collapsedEpisodeGroups) private var collapsedText = ""

  private var contentInset: CGFloat { measuredInset ?? TrafficLightOffsetReader.contentInset(for: nil) }
  /// 줄 좌우 여백 0: 회색 선택 칸이 줄 끝까지 차서, 글자를 버튼 선에 맞춰도 칸이 잘리지 않는다.
  private static let rowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
  var body: some View {
    ScrollViewReader { proxy in
      list
        .onChange(of: selection, initial: true) { show(selection, with: proxy) }
    }
  }

  private var list: some View {
    List {
      // 시스템 구역 제목은 줄과 왼쪽 시작점이 달라 번호와 맞출 수 없어서, 같은 여백을 쓰는 제목 줄을 직접 둔다.
      Text("회차")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.inkMuted)
        .padding(.leading, contentInset)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 줄 왼쪽 끝에서 잰다. 여백이 바뀌어도 줄 끝은 그대로라 값이 흔들리지 않는다.
        .background(TrafficLightOffsetReader { measuredInset = TrafficLightOffsetReader.contentInset(for: $0) })
        .listRowInsets(Self.rowInsets)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
      Section {
        ForEach(rows) { row in
          switch row {
          case .group(let group, let count, let collapsed):
            groupHeader(group, count: count, collapsed: collapsed)
              .moveDisabled(true)
          case .episode(let episode, let number, _, let inGroup):
            episodeRow(episode, number: number, inGroup: inGroup)
          }
        }
        // 드래그로 순서 바꾸기(보이는 줄 번호 그대로 넘긴다). 번호는 순서로 매기므로 함께 바뀐다(파일 이름은 그대로).
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

  private var grouping: EpisodeGrouping.List { .init(episodes: episodes, groups: groups) }
  private var collapsed: Set<GroupID> { Self.collapsedGroups(collapsedText) }

  /// 접힌 묶음(설정 `collapsedEpisodeGroups`, 쉼표로 이은 묶음 ID)
  static func collapsedGroups(_ text: String) -> Set<GroupID> {
    Set(text.split(separator: ",").map { GroupID(rawValue: String($0)) })
  }
  private var rows: [EpisodeGrouping.Row] { EpisodeGrouping.rows(grouping, collapsed: collapsed) }

  private func toggleCollapsed(_ group: GroupID) {
    var set = collapsed
    if !set.insert(group).inserted { set.remove(group) }
    collapsedText = set.map(\.rawValue).sorted().joined(separator: ",")
  }

  /// 묶음 제목 줄: ▸/▾ + 이름 + 회차 수. 누르면 접고 편다. 두 번 누르면 이름 변경.
  private func groupHeader(_ group: EpisodeGroup, count: Int, collapsed: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "chevron.right")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color.inkMuted)
        .rotationEffect(.degrees(collapsed ? 0 : 90))
        .frame(width: 12)
      Text(group.title)
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
      Spacer(minLength: 4)
      Text("\(count)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
    }
    .padding(.leading, contentInset - 2)
    .padding(.trailing, contentInset)
    .padding(.top, 8)
    .padding(.bottom, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { onRenameGroup?(group.id) }
    .simultaneousGesture(TapGesture().onEnded { toggleCollapsed(group.id) })
    .contextMenu {
      if let onRenameGroup, let onUngroup {
        Button("묶음 이름 변경…") { onRenameGroup(group.id) }
        Button("묶음 풀기") { onUngroup(group.id) }
      }
    }
    .listRowInsets(Self.rowInsets)
    .listRowBackground(Color.clear)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityValue(collapsed ? "접힘" : "펼침")
    .accessibilityAction { toggleCollapsed(group.id) }
  }

  private func episodeRow(_ episode: EpisodeMeta, number: Int, inGroup: Bool) -> some View {
    EpisodeRowCell(
      number: number, title: episode.title,
      box: countBox?(episode.id), fallbackCount: episode.characterCount,
      basis: showsCount ? basis : nil,
      isSelected: episode.id == selection || marked.contains(episode.id), inset: contentInset,
      indent: inGroup ? Self.groupIndent : 0)
      // 두 번 클릭하면 이름 변경. 한 번 클릭 선택은 두 번 클릭 판정을 기다리지 않고 바로 한다.
      .onTapGesture(count: 2) { onRename?(episode.id) }
      // ⌘클릭: 고른 것에 넣고 빼기. ⇧클릭: 지금 회차부터 여기까지. 그냥 클릭: 이 회차만.
      .simultaneousGesture(
        TapGesture().modifiers(.command).onEnded { toggleMarked(episode.id) }
          .exclusively(before: TapGesture().modifiers(.shift).onEnded { markRange(to: episode.id) })
          .exclusively(before: TapGesture().onEnded {
            selection = episode.id
            marked = [episode.id]
            isFocused = true
          }))
      .contextMenu { episodeMenu(episode) }
      .listRowInsets(Self.rowInsets)
      .listRowBackground(Color.clear)
      .accessibilityAddTraits(episode.id == selection ? [.isButton, .isSelected] : .isButton)
  }

  /// 우클릭 메뉴. 여러 개 고른 회차 위에서 열면 묶기·묶음에 넣기는 고른 회차 모두에 한다.
  @ViewBuilder
  private func episodeMenu(_ episode: EpisodeMeta) -> some View {
    if let onAddAfter, let onRename, let onTrash, let onSetGoal {
      let targets = marked.contains(episode.id) ? marked : [episode.id]
      Button("아래에 새 회차") { onAddAfter(episode.id) }
      Button("이름 변경…") { onRename(episode.id) }
      if let onBatchRename, targets.count > 1 {
        Button("\(targets.count)개 회차 이름 변경…") { onBatchRename(targets) }
      }
      Button("목표 글자 수…") { onSetGoal(episode.id) }
      Divider()
      if let onGroup {
        Button(targets.count > 1 ? "\(targets.count)개 회차 묶기…" : "묶기…") { onGroup(targets) }
      }
      if let onAddToGroup, !groups.isEmpty {
        Menu("묶음에 넣기") {
          ForEach(groups) { group in
            Button(group.title) { onAddToGroup(targets, group.id) }
          }
        }
      }
      if let onUngroup, let group = episode.group {
        Button("묶음 풀기") { onUngroup(group) }
      }
      Divider()
      Button("휴지통으로 이동…") { onTrash(episode.id) }
    }
  }

  private func toggleMarked(_ id: EpisodeID) {
    if marked.isEmpty, let selection { marked = [selection] }
    if marked.contains(id), marked.count > 1 {
      marked.remove(id)
    } else {
      marked.insert(id)
    }
    isFocused = true
  }

  /// 지금 회차(편집기에 열린 것)부터 누른 회차까지 보이는 회차를 모두 고른다(접힌 묶음 안은 빼고).
  private func markRange(to id: EpisodeID) {
    guard let anchor = selection, episodes.contains(where: { $0.id == anchor }) else { return toggleMarked(id) }
    marked = Set(EpisodeGrouping.visibleRange(from: anchor, to: id, in: grouping, collapsed: collapsed))
    isFocused = true
  }

  /// 고른 회차 줄이 보이게 스크롤한다(작품을 열 때, 메뉴·단축키·검색 결과로 옮길 때). 접힌 묶음 안이면 묶음을 편다.
  /// 펼친 줄은 다음 화면 갱신에 생겨서 스크롤은 한 차례 뒤에 한다.
  private func show(_ id: EpisodeID?, with proxy: ScrollViewProxy) {
    guard let id, let episode = episodes.first(where: { $0.id == id }) else { return }
    if let group = episode.group, collapsed.contains(group) { toggleCollapsed(group) }
    DispatchQueue.main.async { proxy.scrollTo(EpisodeGrouping.Row.id(of: id)) }
  }

  private static let groupIndent: CGFloat = 12

  private func move(by offset: Int) -> KeyPress.Result {
    guard let selection,
      let next = EpisodeGrouping.visibleNeighbor(of: selection, step: offset, in: grouping, collapsed: collapsed)
    else { return .ignored }
    self.selection = next
    marked = [next]
    return .handled
  }
}

/// 회차 한 줄의 보이는 부분: 글자 + 회색 선택 칸 + 클릭 영역.
/// 글자 수는 회차마다 따로 있는 칸(`EpisodeCountBox`)에서 읽는다. 타이핑 중에는 0.2초마다 지금 회차의 글자 수 하나만
/// 바뀌는데, 이 줄만 다시 그려지고 나머지 줄과 작업 공간은 그대로다.
private struct EpisodeRowCell: View {
  let number: Int
  let title: String
  let box: EpisodeCountBox?
  let fallbackCount: CharacterCount?
  /// nil이면 글자 수를 숨긴다(설정).
  let basis: CharacterCountBasis?
  let isSelected: Bool
  let inset: CGFloat
  /// 묶음 안 회차는 조금 들여 쓴다(번호 칸 앞).
  var indent: CGFloat = 0

  private var count: Int? {
    guard let basis else { return nil }
    return (box?.value ?? fallbackCount)?.value(for: basis)
  }

  var body: some View {
    // 클릭 영역 = 회색 선택 칸 전체. 줄 여백을 0으로 하고 여백을 칸 안쪽에 직접 넣어
    // 글자뿐 아니라 칸의 빈 곳을 눌러도 선택되게 한다.
    EpisodeRow(number: number, title: title, count: count)
      .padding(.leading, indent)
      .padding(.horizontal, inset)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .rowHighlight(isSelected: isSelected)
      // 회색 칸 사이의 1pt 틈도 클릭 영역에 넣는다. 틈을 줄 여백(listRowInsets)으로 두면
      // 그곳을 누를 때 아무 반응이 없어 목록이 버벅이는 것처럼 느껴진다.
      .padding(.vertical, 1)
      .contentShape(Rectangle())
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
