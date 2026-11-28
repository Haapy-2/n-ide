import Foundation

/// Contents of `project.json`: project information and per-project settings. Episode bodies aren't here; they're in `episodes/`.
public struct ProjectFile: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var title: String
  /// Array order is episode order. Episode numbers (1화, 2화…) aren't stored; they come from this order.
  public var episodes: [EpisodeMeta]
  public var notes: [NoteMeta]
  public var settings: ProjectSettings
  /// Episode group names (format 2). Which episode belongs to which group is in the episode's `group`.
  /// Groups are always contiguous episodes, and groups without members aren't kept (`EpisodeGrouping.normalized`).
  public var groups: [EpisodeGroup]
  /// Image names the writer sees (decision 52). Manuscript lines and image files carry no names. Order is meaningless (visible order is counted from the manuscript).
  /// Not written when empty, so `project.json` of projects without images stays unchanged.
  public var images: [ImageMeta]

  public init(
    title: String,
    episodes: [EpisodeMeta] = [],
    notes: [NoteMeta] = [],
    settings: ProjectSettings = ProjectSettings(),
    groups: [EpisodeGroup] = [],
    images: [ImageMeta] = []
  ) {
    self.schemaVersion = ProjectFormat.currentSchemaVersion
    self.title = title
    self.episodes = episodes
    self.notes = notes
    self.settings = settings
    self.groups = groups
    self.images = images
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, title, episodes, notes, settings, groups, images }

  /// Format 1 has no `groups`. Absent means no groups (that's the whole 1 → 2 migration).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Once read, an old format is the current format. The next save writes the current version (newer versions are rejected before reading).
    _ = try container.decode(Int.self, forKey: .schemaVersion)
    schemaVersion = ProjectFormat.currentSchemaVersion
    title = try container.decode(String.self, forKey: .title)
    // If the same ID appears twice (hand edits or sync glitches), keep only the first (lookups by ID assume uniqueness).
    // Body files of dropped entries are untouched. The cleaned list is written on the next save.
    episodes = Self.firstOfEach(try container.decode([EpisodeMeta].self, forKey: .episodes))
    notes = try container.decode([NoteMeta].self, forKey: .notes)
    settings = try container.decode(ProjectSettings.self, forKey: .settings)
    groups = Self.firstOfEach(try container.decodeIfPresent([EpisodeGroup].self, forKey: .groups) ?? [])
    images = Self.firstOfEach(try container.decodeIfPresent([ImageMeta].self, forKey: .images) ?? [])
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(title, forKey: .title)
    try container.encode(episodes, forKey: .episodes)
    try container.encode(notes, forKey: .notes)
    try container.encode(settings, forKey: .settings)
    try container.encode(groups, forKey: .groups)
    if !images.isEmpty { try container.encode(images, forKey: .images) }
  }

  private static func firstOfEach<Item: Identifiable>(_ items: [Item]) -> [Item] {
    var seen = Set<Item.ID>()
    return items.filter { seen.insert($0.id).inserted }
  }
}

/// One episode group (e.g. "1부 귀환"). Episode files stay put; grouping is visual only (PLAN ch.8 option B).
public struct EpisodeGroup: Codable, Equatable, Sendable, Identifiable {
  public let id: GroupID
  public var title: String

  public init(id: GroupID = .make(), title: String) {
    self.id = id
    self.title = title
  }
}

/// One image's name. Renaming leaves manuscript lines and image files unchanged (decision 52).
public struct ImageMeta: Codable, Equatable, Sendable, Identifiable {
  public let id: ImageID
  public var name: String

  public init(id: ImageID, name: String) {
    self.id = id
    self.name = name
  }

  /// Initial name from the inserted original file name (extension removed). "그림" if empty.
  public static func name(fromOriginalFileName fileName: String) -> String {
    let name = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "그림" : name
  }
}

/// One episode's info (excluding the body).
public struct EpisodeMeta: Codable, Equatable, Sendable, Identifiable {
  public let id: EpisodeID
  /// Shown as "제목 없음" when empty.
  public var title: String
  /// Goal character count. Which basis (with/without spaces) follows the app setting.
  public var goal: Int
  /// Last counted body length. Kept so the sidebar can show it without reading the body (recomputable from the body).
  /// nil for projects created before this field existed or episodes never counted.
  public var characterCount: CharacterCount?
  /// Group it belongs to. nil if none (not written to the file either).
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

/// One setting note's info (excluding the body).
public struct NoteMeta: Codable, Equatable, Sendable, Identifiable {
  public let id: NoteID
  public var title: String

  public init(id: NoteID = .make(), title: String = "") {
    self.id = id
    self.title = title
  }
}

/// Per-project settings. App-wide settings like fonts don't live here (PLAN.md decision 6).
public struct ProjectSettings: Codable, Equatable, Sendable {
  public var defaultEpisodeGoal: Int

  public init(defaultEpisodeGoal: Int = 5_000) {
    self.defaultEpisodeGoal = defaultEpisodeGoal
  }
}
