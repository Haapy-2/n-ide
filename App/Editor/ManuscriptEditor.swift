import AppKit
import NovelCore
import SwiftUI

/// SwiftUI에 원고 편집기(ManuscriptTextView)를 붙이는 다리.
///
/// 한글 입력 보호 규칙(SPEC 9장):
/// - 본문의 원본은 NSTextView의 텍스트 저장소다. SwiftUI 상태로 본문을 흘려보내지 않는다.
/// - `updateNSView`는 SwiftUI가 아무 때나 부르므로 여기서 텍스트를 다시 넣지 않는다.
///   본문은 회차가 바뀌었을 때(`content.token`이 바뀔 때) 단 한 번만 넣는다.
struct ManuscriptEditor: NSViewRepresentable {
  /// 화면에 올릴 회차 본문. token이 바뀔 때만 편집기에 들어간다.
  struct Content: Equatable {
    let token: UUID
    let episodeID: EpisodeID
    let text: String
  }

  let content: Content
  var style = EditorStyle()
  var showsLineNumbers = false
  var caret = CaretStyle()
  /// 검색 결과로 가기. 같은 회차의 본문이 올라간 뒤 token마다 한 번만 한다.
  var reveal: TextReveal?
  /// 사용자가 글을 고칠 때마다 (자동 저장용).
  var onTextChange: () -> Void = {}
  /// 창이 비활성화될 때 (바로 저장용).
  var onFocusLost: () -> Void = {}
  /// 창이 다시 활성화될 때 (외부 변경 확인용).
  var onFocusGained: () -> Void = {}
  /// 편집기가 만들어졌을 때 한 번.
  var onReady: (ManuscriptTextView) -> Void = { _ in }
  /// 회차 본문을 편집기에 넣은 뒤 한 번(바꾼 회차 목록에서 그 회차의 스냅샷 판을 열 때).
  /// 화면 갱신 중에 상태를 바꾸지 않도록 한 차례 뒤에 부른다.
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
    textView.caret = caret
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
    // 조합 중이면 편집기가 본문에 입히는 것을 조합이 끝날 때까지 미룬다(ManuscriptTextView.applyStyle).
    if textView.style != style { textView.style = style }
    // 그림만 바뀌어 조합 중에도 바로 넣어도 된다.
    textView.showsLineNumbers = showsLineNumbers
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

  /// 떠나는 회차의 자리를 기억하고, 새 회차는 기억한 자리로 연다(PLAN 17장 3번). 화면 위치는 창에 붙어 폭이 잡힌 뒤
  /// 한 차례 뒤에 맞춘다(처음 만들 때는 아직 폭이 없어 줄 위치가 다르다). 검색 결과로 가기가 있으면 그것이 이긴다.
  private func apply(_ content: Content, to textView: ManuscriptTextView, coordinator: Coordinator) {
    coordinator.rememberPlace()
    coordinator.appliedToken = content.token
    coordinator.episodeID = content.episodeID
    textView.replaceAllText(with: content.text)
    let revealing = reveal.map { $0.episodeID == content.episodeID && $0.token != coordinator.appliedRevealToken } ?? false
    if !revealing, let place = EpisodeViewStates.shared.state(for: content.episodeID) {
      textView.restoreViewState(place)
      let token = content.token
      DispatchQueue.main.async { [weak textView, weak coordinator] in
        guard let textView, let coordinator, coordinator.appliedToken == token else { return }
        textView.restoreViewState(place)
        coordinator.rememberPlace()
      }
    }
    coordinator.rememberPlace()
    // 이미 창에 붙어 있으면(회차 전환) 지금 초점을 준다. 아직이면(처음 만들 때) viewDidMoveToWindow가 맡는다.
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
      // 앱을 끌 때는 창이 비활성화되지 않을 수 있어 따로 받는다.
      terminateObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.rememberPlace() }
      }
    }

    /// 지금 회차의 커서와 화면 위치를 이 맥에 기억한다.
    func rememberPlace() {
      guard let episodeID, let textView else { return }
      EpisodeViewStates.shared.record(textView.viewState(), for: episodeID)
    }
    var appliedRevealToken: UUID?
    private var resignObserver: NSObjectProtocol?
    private var becomeKeyObserver: NSObjectProtocol?

    // 프로그램이 본문을 바꿀 때(회차 전환)는 불리지 않고, 사용자가 고칠 때만 불린다.
    func textDidChange(_ notification: Notification) {
      parent?.onTextChange()
    }

    /// 편집기가 창에 있을 때: 창 감시를 걸고, 아무도 키보드 초점을 갖고 있지 않으면 편집기가 받는다.
    /// 사이드바처럼 다른 곳이 초점을 갖고 있으면 빼앗지 않는다(사이드바에서 ↑↓·↩·⌘⌫를 이어 쓰게).
    func attach(to window: NSWindow) {
      guard let textView else { return }
      if observedWindow !== window {
        observeWindow(window)
        if let size = LaunchProbe.windowContentSize { window.setContentSize(size) }
      }
      if window.firstResponder == nil || window.firstResponder === window {
        window.makeFirstResponder(textView)
      }
      // 측정 신호는 한 차례 뒤에 찍는다. 창에 붙는 순간은 아직 화면을 그리기 전이라, 바로 찍으면 실행 시간이 실제보다 짧게 나온다.
      if window.firstResponder === textView { DispatchQueue.main.async { LaunchProbe.editorReady() } }
    }

    private weak var observedWindow: NSWindow?

    private func observeWindow(_ window: NSWindow) {
      if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
      if let becomeKeyObserver { NotificationCenter.default.removeObserver(becomeKeyObserver) }
      observedWindow = window
      // 다른 앱에서 돌아오면 이 창이 다시 키 창이 된다. 그때 회차 파일이 앱 밖에서 바뀌었는지 본다.
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
