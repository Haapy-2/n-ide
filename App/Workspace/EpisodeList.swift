import NovelCore
import SwiftUI

/// Sidebar episode list. One row: `number  title  count`. The count uses the goal basis (setting) and can be hidden in Settings.
///
/// The system selection isn't used; a single subtle gray background is drawn by hand.
/// The system selection paints accent blue on click, then turns gray when focus moves to the editor,
/// which looks like a flash, and there's no way to turn that off.
struct EpisodeList: View {
  let episodes: [EpisodeMeta]
  /// Episode group names (PLAN ch.8 option B). Which episode belongs to which group is the episode's `group`.
  var groups: [EpisodeGroup] = []
  @Binding var selection: EpisodeID?
  /// Multiple selected episodes (⌘-click, ⇧-click). Used for grouping. The editor opens only `selection`.
  @Binding var marked: Set<EpisodeID>
  /// Row inner left padding. The "회차" header, numbers and titles all use it to start on the close button's line.
  /// Measured at runtime (nil = not yet) and held by the workspace: re-measuring every time the list swaps with the search panel
  /// would draw once with the default until the value arrives, making text jump sideways.
  @Binding var measuredInset: CGFloat?
  /// nil (preview) = no menus or dragging.
  var onRename: ((EpisodeID) -> Void)? = nil
  /// Right-click `N개 회차 이름 변경…` on multiple selected episodes
  var onBatchRename: ((Set<EpisodeID>) -> Void)? = nil
  var onTrash: ((EpisodeID) -> Void)? = nil
  var onSetGoal: ((EpisodeID) -> Void)? = nil
  var onAddAfter: ((EpisodeID) -> Void)? = nil
  /// Drag to move: visible row indices (including group header rows, `EpisodeGrouping.drop`)
  var onMove: ((IndexSet, Int) -> Void)? = nil
  /// Group (shows a name prompt), ungroup, rename group, add to an existing group
  var onGroup: ((Set<EpisodeID>) -> Void)? = nil
  var onUngroup: ((GroupID) -> Void)? = nil
  var onRenameGroup: ((GroupID) -> Void)? = nil
  var onAddToGroup: ((Set<EpisodeID>, GroupID) -> Void)? = nil
  /// ⌘Z (false) / ⇧⌘Z (true) while the sidebar has focus. Goes through a confirmation instead of undoing directly.
  var onUndoCommand: ((_ isRedo: Bool) -> Void)? = nil
  /// The episode's count box. nil (preview) shows the value in the episode info.
  var countBox: ((EpisodeID) -> EpisodeCountBox)? = nil
  /// Clicking an episode gives the sidebar keyboard focus. With focus: ↑↓ move, ↩ rename, ⌘⌫ trash.
  @FocusState private var isFocused: Bool
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.sidebarShowsCharacterCount) private var showsCount = true
  @AppStorage(AppSettingKey.collapsedEpisodeGroups) private var collapsedText = ""

  private var contentInset: CGFloat { measuredInset ?? TrafficLightOffsetReader.contentInset(for: nil) }
  /// Row horizontal insets 0: the gray selection rect fills to the row end, so aligning text to the button line doesn't clip the rect.
  private static let rowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
  var body: some View {
    ScrollViewReader { proxy in
      list
        .onChange(of: selection, initial: true) { show(selection, with: proxy) }
    }
  }

  private var list: some View {
    List {
      // The system section header starts at a different left edge than rows and can't align with numbers, so a header row with the same padding is used.
      Text("회차")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.inkMuted)
        .padding(.leading, contentInset)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measured from the row's left edge. The edge stays put when padding changes, so the value doesn't wobble.
        .background(TrafficLightOffsetReader { measuredInset = TrafficLightOffsetReader.contentInset(for: $0) })
        .listRowInsets(Self.rowInsets)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
      Section {
        ForEach(rows) { row in
          switch row {
          case .group(let group, let count, let collapsed):
            // With moveDisabled, the macOS list makes no drop slot right above this row, so the first episode of a group
            // couldn't be dragged out of it. Dragging the header row itself is ignored by EpisodeGrouping.drop since it isn't an episode.
            groupHeader(group, count: count, collapsed: collapsed)
          case .episode(let episode, let number, _, let inGroup):
            episodeRow(episode, number: number, inGroup: inGroup)
          }
        }
        // Reorder by drag (visible row indices passed as is). Numbers follow order, so they change too (file names don't).
        .onMove(perform: onMove)
      }
    }
    // Remove the system default minimum row height so no unclickable gaps appear between rows.
    .environment(\.defaultMinListRowHeight, 0)
    .focusable()
    .focused($isFocused)
    // No focus ring (blue outline). The selected episode's gray rect is enough.
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { move(by: -1) }
    .onKeyPress(.downArrow) { move(by: 1) }
    .onKeyPress(.return) {
      guard let selection, let onRename else { return .ignored }
      onRename(selection)
      return .handled
    }
    // ⌘ combos like ⌘⌫ are taken by the menu first and never get here. So the episode menu reads this value
    // and remaps "Move to Trash" to ⌘⌫ only while the sidebar has focus (EpisodeCommands).
    .focusedValue(\.episodeSidebarFocused, isFocused)
    // Catch Edit menu undo/redo here before they climb to the window (to show a confirmation).
    .onCommand(Selector(("undo:"))) { onUndoCommand?(false) }
    .onCommand(Selector(("redo:"))) { onUndoCommand?(true) }
  }

  private var grouping: EpisodeGrouping.List { .init(episodes: episodes, groups: groups) }
  private var collapsed: Set<GroupID> { Self.collapsedGroups(collapsedText) }

  /// Collapsed groups (setting `collapsedEpisodeGroups`, group IDs joined by commas)
  static func collapsedGroups(_ text: String) -> Set<GroupID> {
    Set(text.split(separator: ",").map { GroupID(rawValue: String($0)) })
  }
  private var rows: [EpisodeGrouping.Row] { EpisodeGrouping.rows(grouping, collapsed: collapsed) }

  private func toggleCollapsed(_ group: GroupID) {
    var set = collapsed
    if !set.insert(group).inserted { set.remove(group) }
    collapsedText = set.map(\.rawValue).sorted().joined(separator: ",")
  }

  /// Group header row: ▸/▾ + name + episode count. Click to collapse/expand. Double-click to rename.
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
      // Double-click renames. Single-click selection happens immediately without waiting for double-click detection.
      .onTapGesture(count: 2) { onRename?(episode.id) }
      // ⌘-click: toggle in the selection. ⇧-click: from the current episode to here. Plain click: just this episode.
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

  /// Context menu. Opened on multiple selected episodes, group / add to group apply to all of them.
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
      // Trash works one episode at a time (undo too), so on a multi-selection it says it applies to this row only.
      Button(targets.count > 1 ? "이 회차만 휴지통으로 이동…" : "휴지통으로 이동…") { onTrash(episode.id) }
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

  /// Select all visible episodes from the current one (open in the editor) to the clicked one (excluding those inside collapsed groups).
  private func markRange(to id: EpisodeID) {
    guard let anchor = selection, episodes.contains(where: { $0.id == anchor }) else { return toggleMarked(id) }
    marked = Set(EpisodeGrouping.visibleRange(from: anchor, to: id, in: grouping, collapsed: collapsed))
    isFocused = true
  }

  /// Scroll so the selected row is visible (on project open, and when moving via menu, shortcut or search result). Expands a collapsed group if needed.
  /// Expanded rows appear on the next refresh, so scrolling happens one turn later.
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

/// Visible part of one episode row: text + gray selection rect + hit area.
/// Counts are read from a per-episode box (`EpisodeCountBox`). While typing only the current episode's count changes every 0.2 s,
/// so only this row redraws; other rows and the workspace stay put.
private struct EpisodeRowCell: View {
  let number: Int
  let title: String
  let box: EpisodeCountBox?
  let fallbackCount: CharacterCount?
  /// nil hides the count (setting).
  let basis: CharacterCountBasis?
  let isSelected: Bool
  let inset: CGFloat
  /// Episodes in a group are slightly indented (before the number column).
  var indent: CGFloat = 0

  private var count: Int? {
    guard let basis else { return nil }
    return (box?.value ?? fallbackCount)?.value(for: basis)
  }

  var body: some View {
    // Hit area = the whole gray selection rect. Row insets are 0 and padding goes inside the rect,
    // so clicking the rect's blank area selects, not just the text.
    EpisodeRow(number: number, title: title, count: count)
      .padding(.leading, indent)
      .padding(.horizontal, inset)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .rowHighlight(isSelected: isSelected)
      // The 1 pt gap between gray rects is included in the hit area too. As row insets (listRowInsets) the gap
      // wouldn't respond to clicks, making the list feel laggy.
      .padding(.vertical, 1)
      .contentShape(Rectangle())
  }
}

private struct EpisodeRow: View {
  let number: Int
  let title: String
  /// nil (left blank) for episodes never counted.
  let count: Int?

  var body: some View {
    HStack(spacing: 8) {
      Text("\(number)")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color.inkMuted)
        // Left-aligned: whether 1 or 100, it starts on the same line under the "회차" header, and titles all start on one line too.
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
