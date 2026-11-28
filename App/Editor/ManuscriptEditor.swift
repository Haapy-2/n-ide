import AppKit
import NovelCore
import SwiftUI

/// Bridge attaching the manuscript editor (ManuscriptTextView) to SwiftUI.
///
/// Hangul input protection rules (SPEC ch.9):
/// - The source of truth for the body is NSTextView's text storage. The body is never piped through SwiftUI state.
/// - SwiftUI calls `updateNSView` at arbitrary times, so text is never re-set here.
///   The body is set exactly once, when the episode changes (`content.token` changes).
struct ManuscriptEditor: NSViewRepresentable {
  /// Episode body to show. Enters the editor only when token changes.
  struct Content: Equatable {
    let token: UUID
    let episodeID: EpisodeID
    let text: String
  }

  let content: Content
  var style = EditorStyle()
  var showsLineNumbers = false
  var numbersBlankLines = true
  var multiCursorEnabled = true
  var caret = CaretStyle()
  /// Go to a search result. Done once per token, after that episode's body is loaded.
  var reveal: TextReveal?
  /// On every user edit (for autosave).
  var onTextChange: () -> Void = {}
  /// On window deactivation (for immediate save).
  var onFocusLost: () -> Void = {}
  /// On window reactivation (for the external-change check).
  var onFocusGained: () -> Void = {}
  /// Once, when the editor is created.
  var onReady: (ManuscriptTextView) -> Void = { _ in }
  /// A short message for the writer (toast). When the multi-cursor limit is hit.
  var onNotice: (String) -> Void = { _ in }
  /// Once after an episode body is loaded into the editor (when opening that episode's snapshot panel from the changed-episodes list).
  /// Called one turn later so state isn't changed during a view update.
  var onShown: (EpisodeID) -> Void = { _ in }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = .paper
    let textView = ManuscriptTextView.make()
    textView.style = style
    textView.showsLineNumbers = showsLineNumbers
    textView.numbersBlankLines = numbersBlankLines
    textView.multiCursorEnabled = multiCursorEnabled
    textView.caret = caret
    textView.onNotice = { [weak coordinator = context.coordinator] in coordinator?.parent?.onNotice($0) }
    scrollView.documentView = textView
    textView.delegate = context.coordinator
    context.coordinator.textView = textView
    context.coordinator.parent = self
    textView.onMoveToWindow = { [weak coordinator = context.coordinator] window in
      coordinator?.attach(to: window)
    }
    onReady(textView)
    apply(content, to: textView, coordinator: context.coordinator)
    applyReveal(to: textView, coordinator: context.coordinator)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else { return }
    // During composition, the editor defers applying styles to the body until composition ends (ManuscriptTextView.applyStyle).
    if textView.style != style { textView.style = style }
    // Only drawing changes, so it can apply immediately even during composition.
    textView.showsLineNumbers = showsLineNumbers
    textView.numbersBlankLines = numbersBlankLines
    // Turning it off ends multi-cursor. During composition the ending commits it first (`endMultiCursor`).
    if textView.multiCursorEnabled != multiCursorEnabled { textView.multiCursorEnabled = multiCursorEnabled }
    if textView.caret != caret { textView.caret = caret }
    if context.coordinator.appliedToken != content.token {
      apply(content, to: textView, coordinator: context.coordinator)
    }
    applyReveal(to: textView, coordinator: context.coordinator)
  }

  private func applyReveal(to textView: ManuscriptTextView, coordinator: Coordinator) {
    guard let reveal, reveal.token != coordinator.appliedRevealToken, reveal.episodeID == content.episodeID else { return }
    coordinator.appliedRevealToken = reveal.token
    textView.reveal(reveal)
  }

  /// Remember the left episode's position and open the new one at its remembered position (PLAN ch.17 #3). Scroll is restored one turn later,
  /// after the view is in a window with a width (at creation there's no width yet, so line positions differ). A search-result jump wins.
  private func apply(_ content: Content, to textView: ManuscriptTextView, coordinator: Coordinator) {
    coordinator.rememberPlace()
    coordinator.appliedToken = content.token
    coordinator.episodeID = content.episodeID
    textView.replaceAllText(with: content.text)
    let revealing = reveal.map { $0.episodeID == content.episodeID && $0.token != coordinator.appliedRevealToken } ?? false
    if !revealing, let place = EpisodeViewStates.shared.state(for: content.episodeID) {
      textView.restoreViewState(place)
      let token = content.token
      let restored = textView.selectedRange()
      // If the first key arrived meanwhile (composing or caret moved), don't move: changing the selection during composition breaks Hangul.
      DispatchQueue.main.async { [weak textView, weak coordinator] in
        guard let textView, let coordinator, coordinator.appliedToken == token,
          !textView.hasMarkedText(), textView.selectedRange() == restored
        else { return }
        textView.restoreViewState(place)
        coordinator.rememberPlace()
      }
    }
    coordinator.rememberPlace()
    // If already in a window (episode switch), give focus now. If not yet (at creation), viewDidMoveToWindow handles it.
    if let window = textView.window { coordinator.attach(to: window) }
    let shown = onShown
    let id = content.episodeID
    DispatchQueue.main.async { shown(id) }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    coordinator.rememberPlace()
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    weak var textView: ManuscriptTextView?
    var parent: ManuscriptEditor?
    var appliedToken: UUID?
    var episodeID: EpisodeID?
    private var terminateObserver: NSObjectProtocol?

    override init() {
      super.init()
      // At quit the window may not deactivate, so this is received separately.
      terminateObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.rememberPlace() }
      }
    }

    /// Remember the current episode's caret and scroll position on this Mac.
    func rememberPlace() {
      guard let episodeID, let textView else { return }
      EpisodeViewStates.shared.record(textView.viewState(), for: episodeID)
    }
    var appliedRevealToken: UUID?
    private var resignObserver: NSObjectProtocol?
    private var becomeKeyObserver: NSObjectProtocol?

    // Not called when the program replaces the body (episode switch), only on user edits.
    func textDidChange(_ notification: Notification) {
      parent?.onTextChange()
    }

    /// When the editor is in a window: start window observation, and take keyboard focus if nobody has it.
    /// Don't steal focus from elsewhere, like the sidebar (so ↑↓·↩·⌘⌫ keep working there).
    func attach(to window: NSWindow) {
      guard let textView else { return }
      if observedWindow !== window {
        observeWindow(window)
        if let size = LaunchProbe.windowContentSize { window.setContentSize(size) }
      }
      if window.firstResponder == nil || window.firstResponder === window {
        window.makeFirstResponder(textView)
      }
      // The measurement signal fires one turn later. At window attach nothing is drawn yet, so firing immediately would understate launch time.
      if window.firstResponder === textView { DispatchQueue.main.async { LaunchProbe.editorReady() } }
    }

    private weak var observedWindow: NSWindow?

    private func observeWindow(_ window: NSWindow) {
      if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
      if let becomeKeyObserver { NotificationCenter.default.removeObserver(becomeKeyObserver) }
      observedWindow = window
      // Returning from another app makes this the key window again. Then check whether the episode file changed outside the app.
      becomeKeyObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.parent?.onFocusGained() }
      }
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification, object: window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.rememberPlace()
          self?.parent?.onFocusLost()
        }
      }
    }

    isolated deinit {
      if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
      if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
      if let becomeKeyObserver { NotificationCenter.default.removeObserver(becomeKeyObserver) }
    }
  }
}
