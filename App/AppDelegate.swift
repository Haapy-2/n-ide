import AppKit

/// On quit, finish any running or pending saves before exiting (SPEC ch.6).
/// SwiftUI has no way to delay termination, so we use an AppKit app delegate (AppKit exception file).
/// The screen theme is also applied app-wide here: SwiftUI `preferredColorScheme` must be set per window,
/// and reverting to "system" (nil) doesn't update windows that are already open.
/// Ending text input when clicking outside a field (e.g. the goal in Settings) is also done here. macOS keeps the cursor by default,
/// and SwiftUI has no way to receive "a click anywhere in the window".
/// Window tabs (grouping windows into tabs) are also disabled here. Left on, the View menu only gains unused tab items, and SwiftUI can't turn them off.
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var themeObserver: NSObjectProtocol?
  private var clickMonitor: Any?

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Must be disabled before any window exists so the View menu's tab items are absent from the start.
    NSWindow.allowsAutomaticWindowTabbing = false
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    applyTheme()
    themeObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.applyTheme() }
    }
    clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
      MainActor.assumeIsolated { Self.endFieldEditingIfClickedOutside(event) }
      return event
    }
  }

  /// While editing a single-line field (the window's shared field editor), a click outside that field ends editing.
  /// The typed value is committed and the clicked control (button, slider…) works as usual. The manuscript editor isn't a field editor, so it's unaffected.
  static func endFieldEditingIfClickedOutside(_ event: NSEvent) {
    guard let window = event.window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
      let field = editor.delegate as? NSView
    else { return }
    if !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
      window.makeFirstResponder(nil)
    }
  }

  /// Called on every settings change, but only applies when the value actually changed.
  private func applyTheme() {
    let theme = UserDefaults.standard.string(forKey: AppSettingKey.appTheme).flatMap(AppTheme.init) ?? .system
    let appearance: NSAppearance? = switch theme {
    case .dark: NSAppearance(named: .darkAqua)
    case .light: NSAppearance(named: .aqua)
    case .system: nil
    }
    if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let autosavers = AutosaverRegistry.shared.all
    guard autosavers.contains(where: \.hasWorkBeforeQuit) else { return .terminateNow }
    Task { @MainActor in
      sender.reply(toApplicationShouldTerminate: await finishBeforeQuit(autosavers))
    }
    return .terminateLater
  }

  /// Decide whether to finish pending saves and quit. If saving ultimately failed, ask: retry / export / quit anyway / cancel.
  private func finishBeforeQuit(_ autosavers: [EpisodeAutosaver]) async -> Bool {
    while true {
      switch await finishSaves(autosavers) {
      case .cancelled: return false
      case .exported: return true
      case .finished: break
      }
      let unsaved = autosavers.filter(\.hasUnprotectedChanges)
      if unsaved.isEmpty {
        guard autosavers.contains(where: { $0.hasProjectWork() }) else { return confirmQuitWithConflicts(autosavers) }
        // All manuscripts are saved; only the episode list (project.json) failed. There's no manuscript to export, so only ask whether to quit.
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "회차 목록을 저장하지 못했어요"
        alert.informativeText = "원고는 저장됐지만, 지금 끄면 회차 추가·순서·이름을 바꾼 것이 사라질 수 있어요. 디스크 공간과 작품 폴더 권한을 확인해 주세요."
        alert.addButton(withTitle: "다시 시도")
        alert.addButton(withTitle: "그래도 종료")
        alert.addButton(withTitle: "취소")
        switch alert.runModal() {
        case .alertFirstButtonReturn: continue
        case .alertSecondButtonReturn: return confirmQuitWithConflicts(autosavers)
        default: return false
        }
      }
      let backedUp = unsaved.allSatisfy(\.unprotectedAreBackedUp)
      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "저장하지 못한 원고가 있어요"
      alert.informativeText =
        backedUp
        ? "작품 폴더에 쓰지 못했어요. 원고는 작품 밖에 따로 백업해 두어서, 그래도 끄면 다음에 이 작품을 열 때 되살릴 수 있어요. 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 시도해 보세요."
        : "지금 끄면 마지막으로 고친 내용이 사라져요. 다른 폴더에 .md 파일로 내보내거나, 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 시도해 주세요."
      alert.addButton(withTitle: "다시 시도")
      alert.addButton(withTitle: "다른 곳에 저장…")
      alert.addButton(withTitle: "그래도 종료")
      alert.addButton(withTitle: "취소")
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        continue
      case .alertSecondButtonReturn:
        let exported = SystemDialogs.exportUnsaved(unsaved.flatMap { $0.unsavedManuscripts() })
        if exported { unsaved.forEach { $0.markRescued() } }
        return exported
      case .alertThirdButtonReturn:
        return true
      default:
        return false
      }
    }
  }

  /// Separately warn about episodes with an unresolved external-change conflict. The app-side text is safe in a `conflict` snapshot,
  /// but after quitting the externally changed text shows on next open, so say so and where to recover it, then ask. No retry (saving can't resolve it).
  private func confirmQuitWithConflicts(_ autosavers: [EpisodeAutosaver]) -> Bool {
    let count = autosavers.reduce(0) { $0 + $1.conflictsKeptInSnapshots }
    guard count > 0 else { return true }
    let alert = NSAlert()
    alert.messageText = "바깥에서 바뀐 회차 \(count)개를 아직 고르지 않았어요"
    alert.informativeText = "이 앱에서 쓴 글은 \"충돌\" 스냅샷으로 남아 있어요. 그래도 끄면 다음에 열 때 바깥에서 바뀐 글이 보이고, 이 앱에서 쓴 글은 스냅샷 판에서 되살릴 수 있어요."
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "그래도 종료")
    return alert.runModal() == .alertSecondButtonReturn
  }

  enum FinishOutcome {
    case finished, exported, cancelled
  }

  /// Finish pending saves. When slow (network drive, iCloud, save retries) nothing shows and it looks frozen, so
  /// after 2 seconds say we're waiting and offer export-and-quit / cancel quit. If saving finishes meanwhile, the alert closes by itself.
  private func finishSaves(_ autosavers: [EpisodeAutosaver]) async -> FinishOutcome {
    let finishing = Task { @MainActor in
      for autosaver in autosavers { await autosaver.finish() }
    }
    if await Self.finishes(finishing, within: .seconds(2)) { return .finished }
    switch await SystemDialogs.waitForSaves(until: finishing) {
    case .finished:
      return .finished
    case .cancel:
      return .cancelled
    case .export:
      let manuscripts = autosavers.flatMap { $0.pendingManuscripts() }
      guard SystemDialogs.exportUnsaved(manuscripts) else { return .cancelled }
      autosavers.forEach { $0.markRescued() }
      return .exported
    }
  }

  /// True if `task` finishes within `limit`. Even if late, `task` is not cancelled (saving continues).
  /// Racing with a task group makes the group wait for all children, so the uncancellable `task.value` would never return past the limit.
  static func finishes(_ task: Task<Void, Never>, within limit: Duration) async -> Bool {
    await withCheckedContinuation { continuation in
      let once = ResumeOnce(continuation)
      Task { @MainActor in
        await task.value
        once.resume(true)
      }
      Task { @MainActor in
        try? await Task.sleep(for: limit)
        once.resume(false)
      }
    }
  }
}

/// Resume exactly once with whichever result arrives first.
@MainActor
private final class ResumeOnce {
  private var continuation: CheckedContinuation<Bool, Never>?

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func resume(_ value: Bool) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}
