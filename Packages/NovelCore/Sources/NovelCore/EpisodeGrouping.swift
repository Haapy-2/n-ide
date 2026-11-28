import Foundation

/// Episode group rules. Pure functions taking the episode list and group names and returning a new list.
/// - A group is always contiguous episodes. Grouping scattered episodes gathers them at the first one's position.
/// - Episode numbers run through the whole project regardless of groups (list order).
/// - Groups with no members are removed. Episodes pointing at missing groups become ungrouped.
public enum EpisodeGrouping {
  public struct List: Equatable, Sendable {
    public var episodes: [EpisodeMeta]
    public var groups: [EpisodeGroup]

    public init(episodes: [EpisodeMeta], groups: [EpisodeGroup]) {
      self.episodes = episodes
      self.groups = groups
    }
  }

  /// Fix to satisfy the rules: gather each group's members at the first member's position, and remove empty groups and dangling group marks.
  /// Unchanged if already valid. Even when `project.json` was edited outside the app and scattered, no episode is lost.
  public static func normalized(_ list: List) -> List {
    let known = Set(list.groups.map(\.id))
    var episodes = list.episodes.map { episode in
      var episode = episode
      if let group = episode.group, !known.contains(group) { episode.group = nil }
      return episode
    }
    var placed = Set<GroupID>()
    var ordered: [EpisodeMeta] = []
    ordered.reserveCapacity(episodes.count)
    for episode in episodes {
      guard let group = episode.group else {
        ordered.append(episode)
        continue
      }
      guard placed.insert(group).inserted else { continue }
      ordered.append(contentsOf: episodes.filter { $0.group == group })
    }
    episodes = ordered
    let used = Set(episodes.compactMap(\.group))
    return List(episodes: episodes, groups: list.groups.filter { used.contains($0.id) })
  }

  /// Make the chosen episodes a new group, gathered at the first chosen episode's position in list order (not selection order).
  /// Episodes in another group leave it.
  public static func group(_ ids: Set<EpisodeID>, as group: EpisodeGroup, in list: List) -> List {
    guard let first = list.episodes.firstIndex(where: { ids.contains($0.id) }) else { return list }
    var picked = list.episodes.filter { ids.contains($0.id) }
    for index in picked.indices { picked[index].group = group.id }
    var rest = list.episodes.filter { !ids.contains($0.id) }
    // First episode position = number of unchosen episodes before it
    let insertAt = list.episodes[..<first].count
    rest.insert(contentsOf: picked, at: min(insertAt, rest.count))
    return normalized(List(episodes: rest, groups: list.groups + [group]))
  }

  /// Episodes stay where they are.
  public static func ungroup(_ group: GroupID, in list: List) -> List {
    var episodes = list.episodes
    for index in episodes.indices where episodes[index].group == group { episodes[index].group = nil }
    return normalized(List(episodes: episodes, groups: list.groups))
  }

  /// Appended at the group's end.
  public static func add(_ ids: Set<EpisodeID>, to group: GroupID, in list: List) -> List {
    guard list.groups.contains(where: { $0.id == group }) else { return list }
    let moving = list.episodes.filter { ids.contains($0.id) && $0.group != group }.map { episode in
      var episode = episode
      episode.group = group
      return episode
    }
    guard !moving.isEmpty else { return list }
    var rest = list.episodes.filter { !moving.map(\.id).contains($0.id) }
    let end = (rest.lastIndex { $0.group == group } ?? -1) + 1
    rest.insert(contentsOf: moving, at: end)
    return normalized(List(episodes: rest, groups: list.groups))
  }

  /// Drop visible row `source` before row `destination` (SwiftUI `onMove`'s two values; rows are `rows(list, collapsed:)`).
  /// The moved episode's group is decided by the row right above the drop position (excluding the rows being moved).
  /// ① Right below an expanded group header, or between episodes of the same group → joins that group.
  /// ② Right after a group's last episode → only episodes already in that group stay in it.
  /// ③ Elsewhere (above a group header, right after a collapsed group, between ungrouped episodes) → leaves its group.
  /// Above and below a group header are the same position in the episode list, so only rows can tell them apart.
  public static func drop(_ source: IndexSet, before destination: Int, in list: List, collapsed: Set<GroupID>) -> List {
    let rows = rows(list, collapsed: collapsed)
    let from = IndexSet(source.compactMap { rows.indices.contains($0) ? rows[$0].episodeIndex : nil })
    guard !from.isEmpty else { return list }
    let slot = min(max(destination, 0), rows.count)
    let to: Int =
      switch slot < rows.count ? rows[slot] : nil {
      case .episode(_, _, let index, _): index
      case .group(let group, _, _): list.episodes.firstIndex { $0.group == group.id } ?? list.episodes.count
      case nil: list.episodes.count
      }
    let staying = { (row: Row) in row.episodeIndex.map { !from.contains($0) } ?? true }
    let above = rows[..<slot].last(where: staying)
    let below = rows[slot...].first(where: staying)
    var joins: GroupID?
    var endOf: GroupID?
    switch above {
    case .group(let group, _, false):
      joins = group.id
    case .episode(let episode, _, _, _):
      if let group = episode.group, case .episode(let next, _, _, _) = below, next.group == group {
        joins = group
      } else {
        endOf = episode.group
      }
    default:
      break
    }
    var picked = from.map { list.episodes[$0] }
    for index in picked.indices {
      let own = picked[index].group
      picked[index].group = joins ?? (own != nil && own == endOf ? own : nil)
    }
    var episodes = list.episodes.enumerated().filter { !from.contains($0.offset) }.map(\.element)
    episodes.insert(contentsOf: picked, at: to - from.count(in: 0..<to))
    return normalized(List(episodes: episodes, groups: list.groups))
  }

  /// Visible episode before (`step` -1) / after (+1) `id` in the sidebar. Skips episodes inside collapsed groups.
  /// Even if `id` is inside a collapsed group (collapsed after selection), returns the nearest visible episode in list order.
  public static func visibleNeighbor(of id: EpisodeID, step: Int, in list: List, collapsed: Set<GroupID>) -> EpisodeID? {
    guard let start = list.episodes.firstIndex(where: { $0.id == id }) else { return nil }
    var index = start + step
    while list.episodes.indices.contains(index) {
      if !isHidden(list.episodes[index], collapsed) { return list.episodes[index].id }
      index += step
    }
    return nil
  }

  /// ⇧-click: visible episodes between the two (inclusive) in list order.
  public static func visibleRange(from: EpisodeID, to: EpisodeID, in list: List, collapsed: Set<GroupID>) -> [EpisodeID] {
    guard let a = list.episodes.firstIndex(where: { $0.id == from }), let b = list.episodes.firstIndex(where: { $0.id == to })
    else { return [] }
    return list.episodes[min(a, b)...max(a, b)].filter { !isHidden($0, collapsed) }.map(\.id)
  }

  private static func isHidden(_ episode: EpisodeMeta, _ collapsed: Set<GroupID>) -> Bool {
    episode.group.map(collapsed.contains) ?? false
  }

  // MARK: - Rows shown in the sidebar

  public enum Row: Equatable, Sendable, Identifiable {
    case group(EpisodeGroup, count: Int, collapsed: Bool)
    /// `number` is the project-wide number (from 1), `index` the list position
    case episode(EpisodeMeta, number: Int, index: Int, inGroup: Bool)

    public var id: String {
      switch self {
      case .group(let group, _, _): "g-\(group.id.rawValue)"
      case .episode(let episode, _, _, _): Self.id(of: episode.id)
      }
    }

    /// `id` of an episode row (when the sidebar scrolls to that row)
    public static func id(of episode: EpisodeID) -> String { "e-\(episode.rawValue)" }

    var episodeIndex: Int? {
      if case .episode(_, _, let index, _) = self { return index }
      return nil
    }
  }

  /// Group header rows + episode rows. Episodes in collapsed groups are omitted.
  public static func rows(_ list: List, collapsed: Set<GroupID>) -> [Row] {
    let titles = Dictionary(uniqueKeysWithValues: list.groups.map { ($0.id, $0) })
    var counts: [GroupID: Int] = [:]
    for episode in list.episodes { if let group = episode.group { counts[group, default: 0] += 1 } }
    var rows: [Row] = []
    var current: GroupID?
    for (index, episode) in list.episodes.enumerated() {
      if let group = episode.group, group != current, let meta = titles[group] {
        rows.append(.group(meta, count: counts[group] ?? 0, collapsed: collapsed.contains(group)))
      }
      current = episode.group
      if let group = episode.group, collapsed.contains(group) { continue }
      rows.append(.episode(episode, number: index + 1, index: index, inGroup: episode.group != nil))
    }
    return rows
  }
}
