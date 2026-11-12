import AppKit

/// 앱 종료 때 진행 중이거나 남은 저장을 끝까지 마치고 끈다(SPEC 6장).
/// SwiftUI에는 종료를 잠시 미루는 방법이 없어서 AppKit 앱 대리자를 쓴다(AppKit 예외 파일).
/// 화면 테마도 여기서 앱 전체에 건다: SwiftUI `preferredColorScheme`은 창마다 걸어야 하고,
/// "기기 설정"(nil)으로 되돌릴 때 이미 열린 창이 바뀌지 않는다.
/// 입력 칸(설정 창의 목표 등) 밖을 누르면 입력을 끝내는 것도 여기서 한다. 맥은 원래 커서를 그대로 두고,
/// SwiftUI에는 "창 어디든 누르면"을 받는 방법이 없다(2026-11-12 사용자 요청).
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var themeObserver: NSObjectProtocol?
  private var clickMonitor: Any?
  private var settingsWindowObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    applyTheme()
    themeObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.applyTheme() }
    }
    // SwiftUI 설정 창은 크기 범위를 줘도 창 테두리를 끌 수 없게(크기 조절 꺼짐) 만들어진다(측정으로 확인).
    // 창이 앞에 올 때 크기 조절을 켠다(2026-11-12 사용자 요청: 드래그로 크기 바꾸기).
    settingsWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
    ) { notification in
      // 알림은 메인 큐에서 오므로 창을 메인 스레드에서만 만진다.
      nonisolated(unsafe) let object = notification.object
      MainActor.assumeIsolated {
        guard let window = object as? NSWindow, Self.isSettingsWindow(window) else { return }
        Self.prepareSettingsWindow(window)
      }
    }
    clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
      MainActor.assumeIsolated { Self.endFieldEditingIfClickedOutside(event) }
      return event
    }
  }

  /// SwiftUI `Settings` 장면이 만드는 창. 이름은 SwiftUI가 붙이는 고정 값이다.
  static func isSettingsWindow(_ window: NSWindow) -> Bool {
    window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
  }

  /// 설정 창 크기를 앱 전체에 하나 저장하는 이름(UserDefaults). 작품마다 따로 두지 않는다(2026-11-12 사용자 요청).
  static let settingsFrameName = "NovelEditorSettingsWindow"
  /// 처음 열 때 창 크기(설정 장면 `defaultSize`). 슬라이더와 숫자가 넉넉하고, 13인치 노트북 화면(높이 약 900pt)에서 메뉴 막대·독을 빼도 들어가는 높이.
  static let settingsDefaultSize = NSSize(width: 520, height: 760)

  /// 크기 조절을 켜고, 저장해 둔 크기가 있으면 그 크기로 연다(없으면 `defaultSize`로 뜬 그대로).
  /// 그 뒤로 사용자가 바꾼 크기·위치는 맥이 이 이름으로 저장한다.
  static func prepareSettingsWindow(_ window: NSWindow, defaults: UserDefaults = .standard) {
    if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
    guard window.frameAutosaveName != settingsFrameName else { return }
    let hasSaved = defaults.string(forKey: "NSWindow Frame \(settingsFrameName)") != nil
    if hasSaved {
      window.setFrameUsingName(settingsFrameName)
    } else if let visible = window.screen?.visibleFrame, window.frame.height > visible.height {
      // 처음 크기는 설정 장면의 `defaultSize`가 이미 정했다. 여기서 또 바꾸면 열리자마자 화면을 다시 그리므로
      // 화면보다 클 때만 줄인다.
      var frame = window.frame
      frame.size.height = visible.height
      frame.origin.y = visible.minY
      window.setFrame(frame, display: true)
    }
    window.setFrameAutosaveName(settingsFrameName)
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
    guard autosavers.contains(where: \.hasUnsavedChanges) else { return .terminateNow }
    Task { @MainActor in
      for autosaver in autosavers { await autosaver.flush() }
      if autosavers.contains(where: \.hasUnsavedChanges) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "저장하지 못한 원고가 있어요"
        alert.informativeText = "지금 끄면 마지막으로 고친 내용이 사라져요. 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 시도해 주세요."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "그래도 종료")
        sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
      } else {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }
}
