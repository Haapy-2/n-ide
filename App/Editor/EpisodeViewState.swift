import Foundation
import NovelCore

/// Where to return when reopening an episode: the caret and the character at the top of the screen (UTF-16 offsets). Character offsets, not pixels,
/// so it returns to the same sentence even if font, size or window width changed. `openedAt` picks the last episode when reopening a project.
struct EpisodeViewState: Codable, Equatable {
  var caret: Int
  var top: Int
  var openedAt: Date
}

/// Per-episode positions live in this Mac's settings (UserDefaults), not in project files (not manuscript, differs per Mac).
/// Keyed by episode ID, so it survives moving the project in Finder. Oldest-opened entries are dropped to keep `limit`.
@MainActor
final class EpisodeViewStates {
  /// In measurement/test runs, remember only in memory and don't write to this Mac's settings.
  static let shared = EpisodeViewStates(defaults: LaunchProbe.isMeasuring ? nil : .standard)

  private let defaults: UserDefaults?
  private let limit: Int
  private var states: [String: EpisodeViewState]

  init(defaults: UserDefaults?, limit: Int = 500) {
    self.defaults = defaults
    self.limit = limit
    states =
      defaults?.data(forKey: AppSettingKey.episodeViewStates)
      .flatMap { try? JSONDecoder().decode([String: EpisodeViewState].self, from: $0) } ?? [:]
  }

  func state(for id: EpisodeID) -> EpisodeViewState? {
    states[id.rawValue]
  }

  func record(_ state: EpisodeViewState, for id: EpisodeID) {
    guard states[id.rawValue] != state else { return }
    states[id.rawValue] = state
    if states.count > limit {
      let oldest = states.sorted { $0.value.openedAt < $1.value.openedAt }.prefix(states.count - limit)
      for (key, _) in oldest { states[key] = nil }
    }
    if let defaults, let data = try? JSONEncoder().encode(states) {
      defaults.set(data, forKey: AppSettingKey.episodeViewStates)
    }
  }

  /// The most recently opened of these episodes. nil if no record.
  func lastOpened(among ids: [EpisodeID]) -> EpisodeID? {
    ids.compactMap { id in states[id.rawValue].map { (id, $0.openedAt) } }.max { $0.1 < $1.1 }?.0
  }
}
