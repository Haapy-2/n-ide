import Foundation

/// `project.json`의 내용: 작품에 속한 정보와 작품별 설정. 회차 본문은 여기 없고 `episodes/`에 따로 있다.
public struct ProjectFile: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var title: String
  /// 배열 순서가 곧 회차 순서다. 회차 번호(1화, 2화…)는 저장하지 않고 이 순서로 매긴다.
  public var episodes: [EpisodeMeta]
  public var notes: [NoteMeta]
  public var settings: ProjectSettings

  public init(
    title: String,
    episodes: [EpisodeMeta] = [],
    notes: [NoteMeta] = [],
    settings: ProjectSettings = ProjectSettings()
  ) {
    self.schemaVersion = ProjectFormat.currentSchemaVersion
    self.title = title
    self.episodes = episodes
    self.notes = notes
    self.settings = settings
  }
}

/// 회차 하나의 정보 (본문 제외).
public struct EpisodeMeta: Codable, Equatable, Sendable, Identifiable {
  public let id: EpisodeID
  /// 비어 있으면 화면에 "제목 없음"으로 보인다.
  public var title: String
  /// 목표 글자 수. 어떤 기준(공백 포함/제외)으로 셀지는 앱 설정을 따른다.
  public var goal: Int

  public init(id: EpisodeID = .make(), title: String = "", goal: Int) {
    self.id = id
    self.title = title
    self.goal = goal
  }
}

/// 설정 노트 하나의 정보 (본문 제외).
public struct NoteMeta: Codable, Equatable, Sendable, Identifiable {
  public let id: NoteID
  public var title: String

  public init(id: NoteID = .make(), title: String = "") {
    self.id = id
    self.title = title
  }
}

/// 작품별 설정. 글꼴 같은 앱 전체 설정은 여기 두지 않는다 (PLAN.md 결정 사항 6).
public struct ProjectSettings: Codable, Equatable, Sendable {
  /// 새 회차를 만들 때 쓰는 목표 글자 수.
  public var defaultEpisodeGoal: Int

  public init(defaultEpisodeGoal: Int = 5_000) {
    self.defaultEpisodeGoal = defaultEpisodeGoal
  }
}
