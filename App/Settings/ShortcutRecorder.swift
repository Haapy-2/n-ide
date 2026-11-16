import AppKit
import SwiftUI

/// 단축키 칸. 누르면 "키를 누르세요"로 바뀌고, 다음 키 누름을 메뉴보다 먼저 받아 넘긴다.
/// AppKit을 쓰는 이유: SwiftUI의 키 입력(onKeyPress)은 ⌘ 조합을 메뉴가 먼저 가져가서 받을 수 없다.
/// 앱 전체 키 누름을 엿보는 감시(NSEvent 로컬 감시)는 기록하는 동안에만 켠다.
struct ShortcutRecorder: View {
  enum Outcome {
    case recorded(KeyCombo)
    /// ⌫: 단축키 없애기
    case cleared
    /// Esc, 칸을 다시 누름, 창을 떠남
    case cancelled
  }

  let combo: KeyCombo?
  let isRecording: Bool
  let onStart: () -> Void
  let onFinish: (Outcome) -> Void
  @State private var monitor = KeyDownMonitor()

  var body: some View {
    Button {
      if isRecording { onFinish(.cancelled) } else { onStart() }
    } label: {
      Text(isRecording ? "키를 누르세요" : combo?.displayText ?? "없음")
        .monospacedDigit()
        .foregroundStyle(isRecording || combo == nil ? .secondary : .primary)
        .frame(minWidth: 96)
    }
    .accessibilityLabel(isRecording ? "키를 누르세요" : "단축키 \(combo?.displayText ?? "없음")")
    .onChange(of: isRecording, initial: true) {
      if isRecording { monitor.start(handle) } else { monitor.stop() }
    }
    .onDisappear {
      if isRecording { onFinish(.cancelled) }
      monitor.stop()
    }
  }

  private func handle(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var modifiers: KeyCombo.Modifiers = []
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.command) { modifiers.insert(.command) }
    guard let key = KeyCombo.key(forKeyCode: event.keyCode) else {
      NSSound.beep()
      return
    }
    if modifiers.isEmpty, key == .escape { return onFinish(.cancelled) }
    if modifiers.isEmpty, key == .delete { return onFinish(.cleared) }
    onFinish(.recorded(KeyCombo(key, modifiers)))
  }
}

/// 기록하는 동안 앱의 키 누름을 가로챈다(메뉴·입력 칸으로 가지 않게 삼킨다).
@MainActor
private final class KeyDownMonitor {
  private var token: Any?

  func start(_ handler: @escaping (NSEvent) -> Void) {
    stop()
    token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handler(event)
      return nil
    }
  }

  func stop() {
    if let token { NSEvent.removeMonitor(token) }
    token = nil
  }
}
