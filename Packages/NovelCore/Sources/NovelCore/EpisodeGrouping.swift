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

  /// 묶음을 푼다. 회차는 그 자리에 그대로 남는다.
  public static func ungroup(_ group: GroupID, in list: List) -> List {
    var episodes = list.episodes
    for index in episodes.indices where episodes[index].group == group { episodes[index].group = nil }
    return normalized(List(episodes: episodes, groups: list.groups))
  }

  /// 회차들을 이미 있는 묶음에 넣는다. 묶음의 끝에 붙는다.
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

  /// 드래그로 옮긴 뒤 묶음 정하기. 옮긴 회차는
  /// ① 앞뒤 회차가 같은 묶음이면(묶음 한가운데에 놓음) 그 묶음에 들어가고,
  /// ② 아니면 제 묶음의 끝에 붙어 있을 때만 제 묶음에 남고,
  /// ③ 그 밖에는 묶음에서 빠진다.
  public static func moved(_ ids: Set<EpisodeID>, in list: List) -> List {
    var episodes = list.episodes
    for index in episodes.indices where ids.contains(episodes[index].id) {
      var before = index - 1
      while before >= 0, ids.contains(episodes[before].id) { before -= 1 }
      var after = index + 1
      while after < episodes.count, ids.contains(episodes[after].id) { after += 1 }
      let previous = before >= 0 ? episodes[before].group : nil
      let next = after < episodes.count ? episodes[after].group : nil
      let own = list.episodes[index].group
      if let previous, previous == next {
        episodes[index].group = previous
      } else if let own, own == previous || own == next {
        episodes[index].group = own
      } else {
        episodes[index].group = nil
      }
    }
    return normalized(List(episodes: episodes, groups: list.groups))
  }

  // MARK: - 사이드바에 보일 줄

  public enum Row: Equatable, Sendable, Identifiable {
    case group(EpisodeGroup, count: Int, collapsed: Bool)
    /// `number`는 작품 전체 번호(1부터), `index`는 목록 자리
    case episode(EpisodeMeta, number: Int, index: Int, inGroup: Bool)

    public var id: String {
      switch self {
      case .group(let group, _, _): "g-\(group.id.rawValue)"
      case .episode(let episode, _, _, _): "e-\(episode.id.rawValue)"
      }
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
