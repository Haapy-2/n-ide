import Foundation

/// 작품 선택 창의 "최근 작품" 목록. 앱 설정(UserDefaults)에 경로와 표시용 정보만 남긴다.
/// 작품을 따로 추적하지 않으므로(PLAN.md 결정 사항 8), 경로가 없어진 항목은 읽을 때 조용히 뺀다.
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

  /// 최근에 연 순서. 경로가 없어진 항목은 빼고 돌려준다(원고는 건드리지 않음).
  static func load(defaults: UserDefaults = .standard) -> [RecentProject] {
    guard let data = defaults.data(forKey: key),
      let items = try? JSONDecoder().decode([RecentProject].self, from: data)
    else { return [] }
    let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
    if existing.count != items.count { save(existing, defaults: defaults) }
    return existing
  }

  /// 작품을 열 때마다 맨 앞으로 올린다.
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
