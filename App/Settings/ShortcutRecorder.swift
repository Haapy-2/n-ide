import AppKit
import SwiftUI

/// Shortcut field. Clicking switches to "press a key" and intercepts the next key press before the menu does.
/// Why AppKit: SwiftUI key input (onKeyPress) can't receive ⌘ combos because the menu takes them first.
/// An app-wide key press monitor (NSEvent local monitor) is on only while recording.
struct ShortcutRecorder: View {
  enum Outcome {
    case recorded(KeyCombo)
    /// ⌫: remove the shortcut
    case cleared
    /// Esc, clicking the field again, leaving the window
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
      Text(isRecording ? "키를 누르세요…" : combo?.displayText ?? "없음")
        .monospacedDigit()
        .foregroundStyle(isRecording ? Color.accent : combo == nil ? .secondary : .primary)
        .frame(minWidth: 96)
    }
    // A waiting field that looks like a normal one gives no hint that a key can be pressed, so it gets an accent border.
    .overlay {
      if isRecording {
        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accent, lineWidth: 2)
      }
    }
    .accessibilityLabel(isRecording ? "키를 누르세요" : "단축키 \(combo?.displayText ?? "없음")")
    .onChange(of: isRecording, initial: true) {
      if isRecording {
        monitor.start(handle, onOtherWindow: { onFinish(.cancelled) })
      } else {
        monitor.stop()
      }
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

/// While recording, intercept Settings window key presses (swallow them so they don't reach menus or fields).
/// The monitor is app-wide, so keys pressed in another window (manuscript) aren't swallowed; recording is cancelled instead.
/// Otherwise, returning to the manuscript window with Settings still recording, neither ⌘S nor typing would reach the manuscript.
@MainActor
private final class KeyDownMonitor {
  private var token: Any?

  func start(_ handler: @escaping (NSEvent) -> Void, onOtherWindow: @escaping () -> Void) {
    stop()
    // Right after clicking the field, the key window is the Settings window.
    weak let window = NSApp.keyWindow
    token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.window === window else {
        onOtherWindow()
        return event
      }
      handler(event)
      return nil
    }
  }

  func stop() {
    if let token { NSEvent.removeMonitor(token) }
    token = nil
  }
}
