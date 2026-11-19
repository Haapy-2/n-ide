import Foundation
import Testing
@testable import NovelCore

struct EpisodeGroupingTests {
  /// 1화~n화. 제목이 곧 원래 번호라 순서를 읽기 쉽다.
  private func list(_ count: Int, groups: [EpisodeGroup] = []) -> EpisodeGrouping.List {
    EpisodeGrouping.List(episodes: (1...count).map { EpisodeMeta(title: "\($0)", goal: 5_000) }, groups: groups)
  }

  private func titles(_ list: EpisodeGrouping.List) -> [String] { list.episodes.map(\.title) }
  private func members(_ list: EpisodeGrouping.List, _ group: GroupID) -> [String] {
    list.episodes.filter { $0.group == group }.map(\.title)
  }
  private func ids(_ list: EpisodeGrouping.List, _ titles: String...) -> Set<EpisodeID> {
    Set(list.episodes.filter { titles.contains($0.title) }.map(\.id))
  }

  @Test func groupingSeparatedEpisodesGathersThemAtTheFirst() {
    let start = list(8)
    let part = EpisodeGroup(title: "1부")

    let result = EpisodeGrouping.group(ids(start, "3", "7"), as: part, in: start)

    #expect(titles(result) == ["1", "2", "3", "7", "4", "5", "6", "8"])
    #expect(members(result, part.id) == ["3", "7"])
    #expect(result.groups == [part])
  }

  /// 한 묶음 가운데 회차를 빼서 새로 묶어도 원래 묶음은 이어진 채로 남는다.
  @Test func groupingFromInsideAnotherGroupKeepsBothContiguous() {
    var start = list(6)
    let first = EpisodeGroup(title: "1부")
    start = EpisodeGrouping.group(ids(start, "1", "2", "3"), as: first, in: start)
    let second = EpisodeGroup(title: "외전")

    let result = EpisodeGrouping.group(ids(start, "2", "5"), as: second, in: start)

    #expect(members(result, first.id) == ["1", "3"])
    #expect(members(result, second.id) == ["2", "5"])
    #expect(titles(result) == ["1", "3", "2", "5", "4", "6"])
  }

  @Test func ungroupKeepsOrderAndDropsTheGroup() {
    let part = EpisodeGroup(title: "1부")
    let start = list(4)
    let grouped = EpisodeGrouping.group(ids(start, "2", "3"), as: part, in: start)

    let result = EpisodeGrouping.ungroup(part.id, in: grouped)

    #expect(titles(result) == titles(grouped))
    #expect(result.groups.isEmpty)
    #expect(result.episodes.allSatisfy { $0.group == nil })
  }

  @Test func addPutsEpisodesAtTheEndOfTheGroup() {
    let part = EpisodeGroup(title: "1부")
    let start = list(5)
    let grouped = EpisodeGrouping.group(ids(start, "1", "2"), as: part, in: start)

    let result = EpisodeGrouping.add(ids(grouped, "5"), to: part.id, in: grouped)

    #expect(titles(result) == ["1", "2", "5", "3", "4"])
    #expect(members(result, part.id) == ["1", "2", "5"])
  }

  /// 앱 밖에서 고쳐 흩어진 묶음, 없는 묶음 표시, 빈 묶음을 바로잡는다. 회차는 하나도 잃지 않는다.
  @Test func normalizeRepairsScatteredAndDanglingGroups() {
    let part = EpisodeGroup(title: "1부")
    let empty = EpisodeGroup(title: "빈 묶음")
    var start = list(5, groups: [part, empty])
    start.episodes[0].group = part.id
    start.episodes[3].group = part.id
    start.episodes[1].group = GroupID(rawValue: "없는-묶음")

    let result = EpisodeGrouping.normalized(start)

    #expect(titles(result) == ["1", "4", "2", "3", "5"])
    #expect(result.episodes[2].group == nil)
    #expect(result.groups == [part])
    #expect(Set(result.episodes.map(\.id)) == Set(start.episodes.map(\.id)))
  }

  // MARK: - 드래그로 옮긴 뒤

  @Test func droppingInsideAGroupJoinsIt() {
    let part = EpisodeGroup(title: "1부")
    let start = list(5)
    var moved = EpisodeGrouping.group(ids(start, "1", "2", "3"), as: part, in: start)
    // 5화를 1화와 2화 사이로 끌어 놓음
    let five = moved.episodes.remove(at: 4)
    moved.episodes.insert(five, at: 1)

    let result = EpisodeGrouping.moved([five.id], in: moved)

    #expect(members(result, part.id) == ["1", "5", "2", "3"])
  }

  @Test func reorderingWithinOwnGroupEdgeKeepsMembership() {
    let part = EpisodeGroup(title: "1부")
    let start = list(4)
    var moved = EpisodeGrouping.group(ids(start, "1", "2"), as: part, in: start)
    // 1화를 묶음 끝(2화 뒤)으로
    let one = moved.episodes.remove(at: 0)
    moved.episodes.insert(one, at: 1)

    let result = EpisodeGrouping.moved([one.id], in: moved)

    #expect(members(result, part.id) == ["2", "1"])
  }

  @Test func draggingOutOfAGroupLeavesIt() {
    let part = EpisodeGroup(title: "1부")
    let start = list(5)
    var moved = EpisodeGrouping.group(ids(start, "1", "2", "3"), as: part, in: start)
    let two = moved.episodes.remove(at: 1)
    moved.episodes.append(two)

    let result = EpisodeGrouping.moved([two.id], in: moved)

    #expect(members(result, part.id) == ["1", "3"])
    #expect(result.episodes.last?.group == nil)
  }

  // MARK: - 사이드바 줄

  @Test func rowsShowHeadersAndHideCollapsedMembersButKeepNumbers() {
    let part = EpisodeGroup(title: "1부")
    let start = list(4)
    let grouped = EpisodeGrouping.group(ids(start, "2", "3"), as: part, in: start)

    let open = EpisodeGrouping.rows(grouped, collapsed: [])
    let closed = EpisodeGrouping.rows(grouped, collapsed: [part.id])

    #expect(open.count == 5)
    #expect(open[1] == .group(part, count: 2, collapsed: false))
    #expect(closed.count == 3)
    // 접어도 4화의 번호는 4다(작품 전체 번호).
    guard case .episode(let episode, let number, _, let inGroup) = closed[2] else {
      Issue.record("4화 줄이 아님")
      return
    }
    #expect(episode.title == "4" && number == 4 && !inGroup)
  }

  // MARK: - 저장 형식

  @Test func versionOneFileReadsWithoutGroupsAndSavesAsVersionTwo() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let old = #"{ "schemaVersion" : 1, "title" : "옛 작품", "episodes" : [ { "id" : "a", "title" : "1화", "goal" : 5000 } ], "notes" : [], "settings" : { "defaultEpisodeGoal" : 5000 } }"#
    try Data(old.utf8).write(to: store.layout.projectFile)

    var project = try store.loadProject()
    #expect(project.groups.isEmpty)
    #expect(project.episodes[0].group == nil)
    let part = EpisodeGroup(title: "1부")
    project.groups = [part]
    project.episodes[0].group = part.id
    try store.saveProject(project)

    let json = try String(contentsOf: store.layout.projectFile, encoding: .utf8)
    #expect(json.contains("\"schemaVersion\" : 2"))
    #expect(try store.loadProject() == project)
  }

  @Test func ungroupedEpisodeDoesNotWriteGroupKey() throws {
    let data = try JSONEncoder().encode(EpisodeMeta(title: "1화", goal: 5_000))
    #expect(!String(decoding: data, as: UTF8.self).contains("group"))
  }
}
