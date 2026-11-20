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
      for autosaver in autosavers { await autosaver.finish() }
      if !autosavers.contains(where: \.hasUnsavedChanges), autosavers.contains(where: { $0.hasProjectWork() }) {
        // 원고는 다 저장됐고 회차 목록(project.json)만 못 썼다. 내보낼 원고가 없으니 끌지만 묻는다.
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "회차 목록을 저장하지 못했어요"
        alert.informativeText = "원고는 저장됐지만, 지금 끄면 회차 추가·순서·이름을 바꾼 것이 사라질 수 있어요. 디스크 공간과 작품 폴더 권한을 확인해 주세요."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "그래도 종료")
        sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
      } else if autosavers.contains(where: \.hasUnsavedChanges) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "저장하지 못한 원고가 있어요"
        alert.informativeText = "지금 끄면 마지막으로 고친 내용이 사라져요. 다른 폴더에 .md 파일로 내보내거나, 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 시도해 주세요."
        alert.addButton(withTitle: "다른 곳에 저장…")
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "그래도 종료")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
          let unsaved = autosavers.filter(\.hasUnsavedChanges)
          let exported = SystemDialogs.exportUnsaved(unsaved.flatMap { $0.unsavedManuscripts() })
          if exported { unsaved.forEach { $0.markRescued() } }
          sender.reply(toApplicationShouldTerminate: exported)
        case .alertThirdButtonReturn:
          sender.reply(toApplicationShouldTerminate: true)
        default:
          sender.reply(toApplicationShouldTerminate: false)
        }
      } else {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }
}
