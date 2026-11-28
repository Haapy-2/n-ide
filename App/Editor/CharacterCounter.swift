import AppKit
import NovelCore
import Observation

/// Character count of the current episode (SPEC ch.7 #3, ch.8).
/// - Once edits start, after `interval` (the "count refresh" setting, default 0.2 s) copy the body once and count it all off the main thread.
///   Input arriving meanwhile joins that single count. The number also updates every `interval` while typing.
///   With `interval` 0 (live), count right after that turn's input finishes.
///   Measured 0.3 ms for 5,000 chars and 10 ms for 100k chars, so no incremental counting.
/// - Text storage is read only. Counting during Hangul composition doesn't break it (the composing character counts as one).
/// - Undo and external-change reloads are caught too, via text storage notifications, not just typing.
@MainActor
@Observable
final class CharacterCounter {
  /// Current episode's count, watched by the status bar. Only updated when it changes so the status bar doesn't redraw needlessly.
  private(set) var current: CharacterCount?

  /// Receiver of counts (records into the episode list → sidebar, project.json).
  @ObservationIgnored var onCount: (EpisodeID, CharacterCount) -> Void = { _, _ in }
  @ObservationIgnored private(set) var episodeID: EpisodeID?
  @ObservationIgnored private weak var textView: NSTextView?
  @ObservationIgnored private var observer: NSObjectProtocol?
  @ObservationIgnored private var waiting: Task<Void, Never>?
  /// Latest started count number per episode, so an old count finishing late can't overwrite a newer value.
  @ObservationIgnored private var latest: [EpisodeID: Int] = [:]
  @ObservationIgnored private var generation = 0
  /// Delay between an edit and counting. Changed in Settings.
  @ObservationIgnored var interval: Duration

  init(interval: Duration = .milliseconds(200)) {
    self.interval = interval
  }

  func attach(_ textView: NSTextView) {
    guard self.textView !== textView else { return }
    if let observer { NotificationCenter.default.removeObserver(observer) }
    self.textView = textView
    // Called right where text storage was edited (main thread). Only records the time here.
    observer = NotificationCenter.default.addObserver(
      forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
    ) { [weak self] notification in
      let charactersChanged = (notification.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) ?? false
      guard charactersChanged else { return }
      MainActor.assumeIsolated { self?.textDidChange() }
    }
  }

  /// On opening an episode. `text` is the body just read, `known` the value left in project.json (shown briefly while counting).
  func begin(episode id: EpisodeID, text: String, known: CharacterCount?) {
    finishLeaving()
    episodeID = id
    if current != known { current = known }
    count(text, for: id)
  }

  /// When an episode body failed to open. Clears it so the previous episode's count doesn't linger in the status bar.
  func clear() {
    finishLeaving()
    episodeID = nil
    current = nil
  }

  /// If the episode being left has uncounted input, count now while the editor still holds the old body.
  private func finishLeaving() {
    guard waiting != nil else { return }
    waiting?.cancel()
    waiting = nil
    recountNow()
  }

  private func textDidChange() {
    // Don't create a task per keystroke. If one is already waiting, it counts this input too.
    // While text storage is being edited (inside this notification) don't read the body; defer to at least the next turn.
    guard waiting == nil else { return }
    let interval = interval
    waiting = Task {
      if interval > .zero { try? await Task.sleep(for: interval) }
      if Task.isCancelled { return }
      waiting = nil
      recountNow()
    }
  }

  /// Count the editor's current body now (copy on main, count off main). Performance tests call this too.
  func recountNow() {
    guard let id = episodeID, let textView else { return }
    count(textView.string, for: id)
  }

  private func count(_ text: String, for id: EpisodeID) {
    generation += 1
    let number = generation
    latest[id] = number
    Task {
      let result = await Task.detached { CharacterCount(counting: text) }.value
      guard latest[id] == number else { return }
      latest[id] = nil
      if id == episodeID, current != result { current = result }
      onCount(id, result)
    }
  }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}
