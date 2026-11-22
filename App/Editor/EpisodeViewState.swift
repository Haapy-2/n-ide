import Foundation
import NovelCore

/// 회차를 다시 열 때 돌아갈 자리: 커서와 화면 맨 위에 있던 글자(UTF-16 위치). 픽셀이 아니라 글자 위치라
/// 글꼴·크기·창 폭이 바뀌어도 같은 문장으로 돌아간다. `openedAt`으로 작품을 다시 열 때 마지막 회차를 고른다.
struct EpisodeViewState: Codable, Equatable {
  var caret: Int
  var top: Int
  var openedAt: Date
}

/// 회차마다의 자리를 이 맥 설정(UserDefaults)에 둔다. 작품 파일에는 쓰지 않는다(원고가 아니고 맥마다 다름).
/// 회차 ID로 찾으므로 Finder에서 작품을 옮겨도 이어진다. 오래 안 연 회차부터 지워 `limit`개만 남긴다.
@MainActor
final class EpisodeViewStates {
  /// 측정·테스트 실행에서는 기억만 하고 이 맥 설정에 쓰지 않는다.
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

  /// 이 회차들 가운데 마지막으로 연 회차. 기록이 없으면 nil.
  func lastOpened(among ids: [EpisodeID]) -> EpisodeID? {
    ids.compactMap { id in states[id.rawValue].map { (id, $0.openedAt) } }.max { $0.1 < $1.1 }?.0
  }
}
