import Foundation

/// `project.json`의 내용: 작품에 속한 정보와 작품별 설정. 회차 본문은 여기 없고 `episodes/`에 따로 있다.
public struct ProjectFile: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var title: String
  /// 배열 순서가 곧 회차 순서다. 회차 번호(1화, 2화…)는 저장하지 않고 이 순서로 매긴다.
  public var episodes: [EpisodeMeta]
  public var notes: [NoteMeta]
  public var settings: ProjectSettings
  /// 회차 묶음의 이름(형식 2). 어느 회차가 어느 묶음인지는 회차의 `group`에 있다.
  /// 묶음은 늘 이어진 회차들이고, 회원이 없는 묶음은 남기지 않는다(`EpisodeGrouping.normalized`).
  public var groups: [EpisodeGroup]

  public init(
    title: String,
    episodes: [EpisodeMeta] = [],
    notes: [NoteMeta] = [],
    settings: ProjectSettings = ProjectSettings(),
    groups: [EpisodeGroup] = []
  ) {
    self.schemaVersion = ProjectFormat.currentSchemaVersion
    self.title = title
    self.episodes = episodes
    self.notes = notes
    self.settings = settings
    self.groups = groups
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, title, episodes, notes, settings, groups }

  /// 형식 1에는 `groups`가 없다. 없으면 묶음 없음으로 읽는다(1 → 2 옮기기는 이것뿐).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // 옛 형식도 읽은 뒤에는 지금 형식이다. 다음 저장 때 지금 버전 번호로 적힌다(더 새 버전은 읽기 전에 거부됨).
    _ = try container.decode(Int.self, forKey: .schemaVersion)
    schemaVersion = ProjectFormat.currentSchemaVersion
    title = try container.decode(String.self, forKey: .title)
    episodes = try container.decode([EpisodeMeta].self, forKey: .episodes)
    notes = try container.decode([NoteMeta].self, forKey: .notes)
    settings = try container.decode(ProjectSettings.self, forKey: .settings)
    groups = try container.decodeIfPresent([EpisodeGroup].self, forKey: .groups) ?? []
  }
}

/// 회차 묶음 하나(예: "1부 귀환"). 회차 파일은 그대로 두고 보이는 것만 묶는다(PLAN 8장 B안).
public struct EpisodeGroup: Codable, Equatable, Sendable, Identifiable {
  public let id: GroupID
  public var title: String

  public init(id: GroupID = .make(), title: String) {
    self.id = id
    self.title = title
  }
}

/// 회차 하나의 정보 (본문 제외).
public struct EpisodeMeta: Codable, Equatable, Sendable, Identifiable {
  public let id: EpisodeID
  /// 비어 있으면 화면에 "제목 없음"으로 보인다.
  public var title: String
  /// 목표 글자 수. 어떤 기준(공백 포함/제외)으로 셀지는 앱 설정을 따른다.
  public var goal: Int
  /// 마지막으로 센 본문 글자 수. 사이드바가 본문을 읽지 않고 보여주려고 둔다(본문에서 다시 셀 수 있는 값).
  /// 이 값이 생기기 전에 만든 작품이나 아직 센 적 없는 회차는 nil.
  public var characterCount: CharacterCount?
  /// 속한 묶음. 없으면 nil(파일에도 적지 않는다).
  public var group: GroupID?

  public init(
    id: EpisodeID = .make(), title: String = "", goal: Int, characterCount: CharacterCount? = nil, group: GroupID? = nil
  ) {
    self.id = id
    self.title = title
    self.goal = goal
    self.characterCount = characterCount
    self.group = group
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
  public var defaultEpisodeGoal: Int

  public init(defaultEpisodeGoal: Int = 5_000) {
    self.defaultEpisodeGoal = defaultEpisodeGoal
  }
}
