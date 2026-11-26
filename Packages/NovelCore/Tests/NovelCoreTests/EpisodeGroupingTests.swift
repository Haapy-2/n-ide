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

  // MARK: - 드래그로 놓기 (줄 번호는 보이는 줄: 묶음 제목 줄 포함)

  @Test func droppingInsideAGroupJoinsIt() {
    let part = EpisodeGroup(title: "1부")
    let start = list(5)
    let grouped = EpisodeGrouping.group(ids(start, "1", "2", "3"), as: part, in: start)
    // 5화를 1화와 2화 사이로 끌어 놓음(줄: 0 1부, 1 「1」, 2 「2」, 3 「3」, 4 「4」, 5 「5」)
    let result = EpisodeGrouping.drop([5], before: 2, in: grouped, collapsed: [])

    #expect(members(result, part.id) == ["1", "5", "2", "3"])
  }

  @Test func reorderingWithinOwnGroupEdgeKeepsMembership() {
    let part = EpisodeGroup(title: "1부")
    let start = list(4)
    let grouped = EpisodeGrouping.group(ids(start, "1", "2"), as: part, in: start)
    // 1화를 묶음 끝(2화 뒤)으로
    let result = EpisodeGrouping.drop([1], before: 3, in: grouped, collapsed: [])

    #expect(members(result, part.id) == ["2", "1"])
  }

  @Test func draggingOutOfAGroupLeavesIt() {
    let part = EpisodeGroup(title: "1부")
    let start = list(5)
    let grouped = EpisodeGrouping.group(ids(start, "1", "2", "3"), as: part, in: start)
    // 2화를 맨 끝으로
    let result = EpisodeGrouping.drop([2], before: 6, in: grouped, collapsed: [])

    #expect(members(result, part.id) == ["1", "3"])
    #expect(result.episodes.last?.group == nil)
  }

  @Test func droppingFirstMemberAboveItsHeaderLeavesTheGroup() {
    let part = EpisodeGroup(title: "1부")
    let start5 = list(5)
    let grouped = EpisodeGrouping.group(ids(start5, "1", "2", "3"), as: part, in: start5)
    // 줄: 0 1부, 1 「1」, 2 「2」, 3 「3」, 4 「4」, 5 「5」. 1화를 묶음 제목 위로
    let result = EpisodeGrouping.drop([1], before: 0, in: grouped, collapsed: [])

    #expect(titles(result) == ["1", "2", "3", "4", "5"])
    #expect(members(result, part.id) == ["2", "3"])
    #expect(result.episodes[0].group == nil)
  }

  @Test func droppingRightBelowHeaderJoinsAsFirstMember() {
    let part = EpisodeGroup(title: "1부")
    let start5 = list(5)
    let grouped = EpisodeGrouping.group(ids(start5, "1", "2", "3"), as: part, in: start5)
    // 4화를 묶음 제목과 1화 사이로
    let result = EpisodeGrouping.drop([4], before: 1, in: grouped, collapsed: [])

    #expect(members(result, part.id) == ["4", "1", "2", "3"])
  }

  @Test func droppingAboveHeaderBelowAnotherGroupJoinsNeither() {
    let first = EpisodeGroup(title: "1부")
    let second = EpisodeGroup(title: "2부")
    let start6 = list(6)
    var grouped = EpisodeGrouping.group(ids(start6, "1", "2", "3"), as: first, in: start6)
    grouped = EpisodeGrouping.group(ids(grouped, "4", "5"), as: second, in: grouped)
    // 줄: 0 1부, 1~3 「1」~「3」, 4 2부, 5 「4」, 6 「5」, 7 「6」. 4화를 2부 제목 위(1부 끝 바로 뒤)로
    let result = EpisodeGrouping.drop([5], before: 4, in: grouped, collapsed: [])

    #expect(titles(result) == ["1", "2", "3", "4", "5", "6"])
    #expect(members(result, first.id) == ["1", "2", "3"])
    #expect(members(result, second.id) == ["5"])
    #expect(result.episodes[3].group == nil)
  }

  @Test func droppingAtGroupEndKeepsOnlyItsOwnMembers() {
    let part = EpisodeGroup(title: "1부")
    let start4 = list(4)
    let grouped = EpisodeGrouping.group(ids(start4, "1", "2"), as: part, in: start4)
    // 줄: 0 1부, 1 「1」, 2 「2」, 3 「3」, 4 「4」
    let own = EpisodeGrouping.drop([1], before: 3, in: grouped, collapsed: [])
    #expect(members(own, part.id) == ["2", "1"])

    let outsider = EpisodeGrouping.drop([4], before: 3, in: grouped, collapsed: [])
    #expect(titles(outsider) == ["1", "2", "4", "3"])
    #expect(members(outsider, part.id) == ["1", "2"])
  }

  @Test func droppingAroundCollapsedGroupStaysOutside() {
    let part = EpisodeGroup(title: "1부")
    let start5 = list(5)
    let grouped = EpisodeGrouping.group(ids(start5, "2", "3"), as: part, in: start5)
    // 줄: 0 「1」, 1 1부(접힘), 2 「4」, 3 「5」
    let below = EpisodeGrouping.drop([3], before: 2, in: grouped, collapsed: [part.id])
    #expect(titles(below) == ["1", "2", "3", "5", "4"])
    #expect(members(below, part.id) == ["2", "3"])

    let above = EpisodeGrouping.drop([3], before: 1, in: grouped, collapsed: [part.id])
    #expect(titles(above) == ["1", "5", "2", "3", "4"])
    #expect(members(above, part.id) == ["2", "3"])
  }

  // MARK: - 보이는 줄로 움직이기

  @Test func neighborSkipsCollapsedMembers() {
    let part = EpisodeGroup(title: "1부")
    let start6 = list(6)
    let grouped = EpisodeGrouping.group(ids(start6, "3", "4"), as: part, in: start6)
    let id = { (title: String) in grouped.episodes.first { $0.title == title }!.id }

    #expect(EpisodeGrouping.visibleNeighbor(of: id("2"), step: 1, in: grouped, collapsed: [part.id]) == id("5"))
    #expect(EpisodeGrouping.visibleNeighbor(of: id("5"), step: -1, in: grouped, collapsed: [part.id]) == id("2"))
    #expect(EpisodeGrouping.visibleNeighbor(of: id("6"), step: 1, in: grouped, collapsed: [part.id]) == nil)
    // 고른 회차가 접힌 묶음 안이면(묶음을 접은 뒤) 가장 가까운 보이는 회차로
    #expect(EpisodeGrouping.visibleNeighbor(of: id("3"), step: 1, in: grouped, collapsed: [part.id]) == id("5"))
    #expect(EpisodeGrouping.visibleNeighbor(of: id("4"), step: -1, in: grouped, collapsed: [part.id]) == id("2"))
    #expect(EpisodeGrouping.visibleNeighbor(of: id("2"), step: 1, in: grouped, collapsed: []) == id("3"))
  }

  @Test func rangeSkipsCollapsedMembers() {
    let part = EpisodeGroup(title: "1부")
    let start6 = list(6)
    let grouped = EpisodeGrouping.group(ids(start6, "3", "4"), as: part, in: start6)
    let id = { (title: String) in grouped.episodes.first { $0.title == title }!.id }

    let range = EpisodeGrouping.visibleRange(from: id("6"), to: id("1"), in: grouped, collapsed: [part.id])
    #expect(range.map { id in grouped.episodes.first { $0.id == id }!.title } == ["1", "2", "5", "6"])
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
