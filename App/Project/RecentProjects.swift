import Foundation

/// The picker's "recent projects" list. Only paths and display info are kept in app settings (UserDefaults).
/// Projects aren't tracked separately (PLAN.md decision 8), so entries whose path is gone are silently dropped when read.
struct RecentProject: Codable, Equatable, Identifiable {
  var path: String
  var title: String
  var episodeCount: Int
  var lastOpened: Date

  var id: String { path }
  var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
}

enum RecentProjects {
  private static let key = "recentProjects"
  private static let limit = 20

  /// Most recently opened first. Entries whose path is gone are dropped (manuscripts untouched).
  static func load(defaults: UserDefaults = .standard) -> [RecentProject] {
    guard let data = defaults.data(forKey: key),
      let items = try? JSONDecoder().decode([RecentProject].self, from: data)
    else { return [] }
    let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
    if existing.count != items.count { save(existing, defaults: defaults) }
    return existing
  }

  /// Moved to the front every time a project opens.
  static func record(url: URL, title: String, episodeCount: Int, defaults: UserDefaults = .standard) {
    let path = url.path(percentEncoded: false)
    var items = load(defaults: defaults).filter { $0.path != path }
    items.insert(RecentProject(path: path, title: title, episodeCount: episodeCount, lastOpened: .now), at: 0)
    save(Array(items.prefix(limit)), defaults: defaults)
  }

  static func remove(_ project: RecentProject, defaults: UserDefaults = .standard) {
    save(load(defaults: defaults).filter { $0.path != project.path }, defaults: defaults)
  }

  private static func save(_ items: [RecentProject], defaults: UserDefaults) {
    defaults.set(try? JSONEncoder().encode(items), forKey: key)
  }
}
