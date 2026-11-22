import AppKit

/// 앱 종료 때 진행 중이거나 남은 저장을 끝까지 마치고 끈다(SPEC 6장).
/// SwiftUI에는 종료를 잠시 미루는 방법이 없어서 AppKit 앱 대리자를 쓴다(AppKit 예외 파일).
/// 화면 테마도 여기서 앱 전체에 건다: SwiftUI `preferredColorScheme`은 창마다 걸어야 하고,
/// "기기 설정"(nil)으로 되돌릴 때 이미 열린 창이 바뀌지 않는다.
/// 입력 칸(설정 창의 목표 등) 밖을 누르면 입력을 끝내는 것도 여기서 한다. 맥은 원래 커서를 그대로 두고,
/// SwiftUI에는 "창 어디든 누르면"을 받는 방법이 없다.
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var themeObserver: NSObjectProtocol?
  private var clickMonitor: Any?

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

  /// 한 줄 입력 칸을 고치는 중(창의 공용 입력기 = field editor)에 그 칸 밖을 누르면 입력을 끝낸다.
  /// 입력한 값은 확정되고, 누른 곳(버튼·슬라이더 등)은 평소대로 동작한다. 원고 편집기는 field editor가 아니라 상관없다.
  static func endFieldEditingIfClickedOutside(_ event: NSEvent) {
    guard let window = event.window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
      let field = editor.delegate as? NSView
    else { return }
    if !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
      window.makeFirstResponder(nil)
    }
  }

  /// 설정이 바뀔 때마다 불리지만 값이 달라졌을 때만 바꾼다.
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

  /// 남은 저장을 마치고 끌지 정한다. 끝내 저장하지 못했으면 다시 시도·내보내기·그래도 종료·취소를 묻는다.
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
        // 원고는 다 저장됐고 회차 목록(project.json)만 못 썼다. 내보낼 원고가 없으니 끌지만 묻는다.
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

  /// 외부 변경 충돌을 고르지 않은 회차가 있으면 따로 알린다. 앱 쪽 글은 `conflict` 스냅샷에 있어 잃지 않지만,
  /// 끄면 다음에 열 때 바깥에서 바뀐 글이 보이므로 그 사실과 되살릴 곳을 말하고 끌지 묻는다. 다시 시도는 두지 않는다(저장으로 풀리지 않는다).
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

  /// 남은 저장을 마친다. 늦으면(네트워크 드라이브·iCloud, 저장 재시도) 아무것도 안 보여 멈춘 것처럼 보이므로,
  /// 2초가 넘으면 기다리는 중임을 알리고 내보내고 끄기·종료 취소를 고르게 한다. 그사이 저장이 끝나면 알림은 저절로 닫힌다.
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

  /// `task`가 `limit` 안에 끝나면 true. 늦어도 `task`는 취소하지 않는다(저장은 계속된다).
  /// 작업 그룹으로 겨루면 그룹이 모든 자식을 기다려서, 취소되지 않는 `task.value` 때문에 한도가 지나도 돌아오지 않는다.
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

/// 둘 중 먼저 온 결과로 한 번만 잇는다.
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
