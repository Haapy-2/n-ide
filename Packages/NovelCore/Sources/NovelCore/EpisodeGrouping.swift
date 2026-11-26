import Foundation

/// 회차 묶음의 규칙. 회차 목록과 묶음 이름만 받아 새 목록을 돌려주는 순수 함수들.
/// - 묶음은 늘 이어진 회차들이다. 떨어진 회차를 묶으면 첫 회차 자리로 모아 붙인다.
/// - 회차 번호는 묶음과 상관없이 작품 전체로 이어진다(목록 순서 그대로).
/// - 회원이 없는 묶음은 지운다. 없는 묶음을 가리키는 회차는 묶음 없음으로 돌린다.
public enum EpisodeGrouping {
  public struct List: Equatable, Sendable {
    public var episodes: [EpisodeMeta]
    public var groups: [EpisodeGroup]

    public init(episodes: [EpisodeMeta], groups: [EpisodeGroup]) {
      self.episodes = episodes
      self.groups = groups
    }
  }

  /// 규칙에 맞게 고친다: 각 묶음의 회원을 첫 회원 자리에 모으고, 빈 묶음과 없는 묶음 표시를 지운다.
  /// 이미 맞으면 그대로다. 앱 밖에서 `project.json`을 고쳐 흩어진 경우에도 회차는 하나도 잃지 않는다.
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

  /// 고른 회차들을 새 묶음으로. 목록에서 맨 앞의 고른 회차 자리로 모은다(고른 순서가 아니라 목록 순서대로).
  /// 다른 묶음에 있던 회차는 그 묶음에서 빠진다.
  public static func group(_ ids: Set<EpisodeID>, as group: EpisodeGroup, in list: List) -> List {
    guard let first = list.episodes.firstIndex(where: { ids.contains($0.id) }) else { return list }
    var picked = list.episodes.filter { ids.contains($0.id) }
    for index in picked.indices { picked[index].group = group.id }
    var rest = list.episodes.filter { !ids.contains($0.id) }
    // 맨 앞 회차 자리 = 그 앞에 있던 고르지 않은 회차 수
    let insertAt = list.episodes[..<first].count
    rest.insert(contentsOf: picked, at: min(insertAt, rest.count))
    return normalized(List(episodes: rest, groups: list.groups + [group]))
  }

  /// 회차는 그 자리에 그대로 남는다.
  public static func ungroup(_ group: GroupID, in list: List) -> List {
    var episodes = list.episodes
    for index in episodes.indices where episodes[index].group == group { episodes[index].group = nil }
    return normalized(List(episodes: episodes, groups: list.groups))
  }

  /// 묶음의 끝에 붙는다.
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

  /// 드래그로 보이는 줄 `source`를 줄 `destination` 앞에 놓는다(SwiftUI `onMove`의 두 값, 줄은 `rows(list, collapsed:)`).
  /// 옮긴 회차의 묶음은 놓은 자리의 바로 위 줄로 정한다(옮기는 줄은 빼고 본다).
  /// ① 펼친 묶음 제목 바로 아래, 또는 같은 묶음 회차 사이 → 그 묶음에 들어간다.
  /// ② 묶음의 마지막 회차 바로 뒤 → 제 묶음이었던 회차만 남는다.
  /// ③ 그 밖(묶음 제목 위, 접힌 묶음 바로 뒤, 묶음 없는 회차 사이) → 묶음에서 빠진다.
  /// 묶음 제목 위와 아래는 회차 목록에서 같은 자리라, 줄로 봐야 둘을 가를 수 있다.
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

  /// 사이드바에서 `id`의 앞(`step` -1)·뒤(+1)에 보이는 회차. 접힌 묶음 안 회차는 건너뛴다.
  /// `id`가 접힌 묶음 안이어도(고른 뒤에 접음) 목록 순서로 가장 가까운 보이는 회차를 준다.
  public static func visibleNeighbor(of id: EpisodeID, step: Int, in list: List, collapsed: Set<GroupID>) -> EpisodeID? {
    guard let start = list.episodes.firstIndex(where: { $0.id == id }) else { return nil }
    var index = start + step
    while list.episodes.indices.contains(index) {
      if !isHidden(list.episodes[index], collapsed) { return list.episodes[index].id }
      index += step
    }
    return nil
  }

  /// ⇧클릭: 두 회차 사이(둘 포함)의 보이는 회차를 목록 순서로.
  public static func visibleRange(from: EpisodeID, to: EpisodeID, in list: List, collapsed: Set<GroupID>) -> [EpisodeID] {
    guard let a = list.episodes.firstIndex(where: { $0.id == from }), let b = list.episodes.firstIndex(where: { $0.id == to })
    else { return [] }
    return list.episodes[min(a, b)...max(a, b)].filter { !isHidden($0, collapsed) }.map(\.id)
  }

  private static func isHidden(_ episode: EpisodeMeta, _ collapsed: Set<GroupID>) -> Bool {
    episode.group.map(collapsed.contains) ?? false
  }

  // MARK: - 사이드바에 보일 줄

  public enum Row: Equatable, Sendable, Identifiable {
    case group(EpisodeGroup, count: Int, collapsed: Bool)
    /// `number`는 작품 전체 번호(1부터), `index`는 목록 자리
    case episode(EpisodeMeta, number: Int, index: Int, inGroup: Bool)

    public var id: String {
      switch self {
      case .group(let group, _, _): "g-\(group.id.rawValue)"
      case .episode(let episode, _, _, _): Self.id(of: episode.id)
      }
    }

    /// 회차 줄의 `id`(사이드바가 그 줄로 스크롤할 때)
    public static func id(of episode: EpisodeID) -> String { "e-\(episode.rawValue)" }

    var episodeIndex: Int? {
      if case .episode(_, _, let index, _) = self { return index }
      return nil
    }
  }

  /// 묶음 제목 줄 + 회차 줄. 접힌 묶음의 회차는 빠진다.
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
