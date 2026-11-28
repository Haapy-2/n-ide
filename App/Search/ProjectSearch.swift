import Foundation
import NovelCore
import Observation

/// State of one project-search panel (PLAN ch.13). Searches off the main thread once typing pauses for 0.2 s.
/// New typing cancels the running search, and the previous result stays until the new one arrives (so the list doesn't flicker).
@MainActor
@Observable
final class ProjectSearch {
  var query = ""
  var caseSensitive = false
  /// Last finished search. nil when the input is cleared.
  private(set) var result: ProjectSearchResult?
  /// The phrase and case sensitivity `result` was found with. Used to re-match in the editor when a result is clicked.
  private(set) var resultQuery = ""
  private(set) var resultCaseSensitive = false
  private(set) var isSearching = false

  @ObservationIgnored private let store: ProjectStore
  /// Episode order (current list)
  @ObservationIgnored private let episodeIDs: () -> [EpisodeID]
  /// Text searched instead of files: the open episode's editor text, and text only in memory after a failed save.
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

  /// When the phrase or options change. Waits briefly, then searches.
  func schedule() {
    start(after: delay)
  }

  /// Search again now without waiting (when reopening the panel: text may have changed meanwhile).
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
      // The body is copied once right before searching (only the open episode, not per keystroke).
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

/// Request sent to the editor when a result is clicked. A new token each time so clicking the same spot jumps again.
struct TextReveal: Equatable {
  let token = UUID()
  let episodeID: EpisodeID
  let location: Int
  let length: Int
  let query: String
  let caseSensitive: Bool
}
