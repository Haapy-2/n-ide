import Foundation
import NovelCore
import Observation

/// 작품 전체 검색 패널 하나의 상태(PLAN 13장). 입력이 0.2초 멈추면 메인 스레드 밖에서 찾는다.
/// 새로 치면 하던 검색은 취소하고, 새 결과가 나올 때까지 앞 결과를 그대로 보여 준다(목록이 깜빡이지 않게).
@MainActor
@Observable
final class ProjectSearch {
  var query = ""
  var caseSensitive = false
  /// 마지막으로 끝난 검색. 입력을 지우면 nil.
  private(set) var result: ProjectSearchResult?
  /// `result`를 찾은 문구와 대소문자 구분. 결과를 누를 때 편집기에서 다시 맞춰 보는 데 쓴다.
  private(set) var resultQuery = ""
  private(set) var resultCaseSensitive = false
  private(set) var isSearching = false

  @ObservationIgnored private let store: ProjectStore
  /// 회차 순서(지금 목록)
  @ObservationIgnored private let episodeIDs: () -> [EpisodeID]
  /// 파일 대신 찾을 글: 열린 회차의 편집기 글, 저장하지 못해 메모리에만 있는 글.
  @ObservationIgnored private let texts: () -> [EpisodeID: String]
  @ObservationIgnored private let delay: Duration
  @ObservationIgnored private var task: Task<Void, Never>?

  init(
    store: ProjectStore, episodeIDs: @escaping () -> [EpisodeID],
    texts: @escaping () -> [EpisodeID: String], delay: Duration = .milliseconds(200)
  ) {
    self.store = store
    self.episodeIDs = episodeIDs
    self.texts = texts
    self.delay = delay
  }

  /// 문구·옵션이 바뀌었을 때. 잠시 기다렸다가 찾는다.
  func schedule() {
    start(after: delay)
  }

  /// 기다리지 않고 지금 다시 찾는다(패널을 다시 열 때: 그사이 글이 바뀌었을 수 있다).
  func refresh() {
    start(after: .zero)
  }

  func cancel() {
    task?.cancel()
    task = nil
    isSearching = false
  }

  private func start(after wait: Duration) {
    task?.cancel()
    let query = query
    let caseSensitive = caseSensitive
    guard TextSearch.isSearchable(query) else {
      task = nil
      isSearching = false
      result = nil
      return
    }
    task = Task {
      if wait > .zero {
        try? await Task.sleep(for: wait)
        guard !Task.isCancelled else { return }
      }
      isSearching = true
      // 본문 복사는 찾기 직전에 한 번(열린 회차 하나, 키 입력마다가 아님).
      let ids = episodeIDs()
      let texts = texts()
      let store = store
      let job = Task.detached(priority: .userInitiated) {
        try store.search(query, in: ids, texts: texts, caseSensitive: caseSensitive)
      }
      let found = await withTaskCancellationHandler { await job.result } onCancel: { job.cancel() }
      guard !Task.isCancelled else { return }
      isSearching = false
      if case .success(let found) = found {
        result = found
        resultQuery = query
        resultCaseSensitive = caseSensitive
      }
    }
  }
}

/// 검색 결과를 눌렀을 때 편집기에 보낼 요청. 같은 곳을 다시 눌러도 다시 가도록 매번 새 token.
struct TextReveal: Equatable {
  let token = UUID()
  let episodeID: EpisodeID
  let location: Int
  let length: Int
  let query: String
  let caseSensitive: Bool
}
