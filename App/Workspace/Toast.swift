import SwiftUI

/// Small notice that briefly appears at the top right of the editor and fades.
/// Shown only inside the window, not as a system notification. Doesn't touch editor focus, selection or Hangul composition.
struct Toast: Identifiable {
  /// Text button on the right of the toast (e.g. "메모 달기"). Pressing it closes the toast.
  struct Action {
    let title: String
    let perform: () -> Void
  }

  let id = UUID()
  let message: String
  /// Gray monochrome SF Symbol name.
  var systemImage = "checkmark"
  var action: Action?
  /// Second text button (`바꾼 곳 보기 · 되돌리기` after replace all)
  var secondAction: Action?
  /// nil uses the toast duration setting. Big operations with an undo button stay longer.
  var duration: Duration?
}

/// One per window. Only one shows at a time; a new notice replaces the previous immediately (no stacking).
/// Disappears after the "toast duration" setting (default 2 s); while hovered it waits, and restarts counting when the mouse leaves.
@MainActor
@Observable
final class ToastCenter {
  private(set) var current: Toast?

  @ObservationIgnored private var isHovering = false
  @ObservationIgnored private var dismissTask: Task<Void, Never>?
  /// nil reads the setting each time it shows (changes apply from the next toast). Tests inject a short value.
  private let fixedDuration: Duration?

  init(duration: Duration? = nil) {
    fixedDuration = duration
  }

  /// Read the setting snapped to 0.5–5 s in 0.5 steps. Default 2 s if absent.
  static func storedDuration(_ defaults: UserDefaults = .standard) -> Duration {
    let setting = EditorSetting.toastDuration
    let seconds = defaults.object(forKey: AppSettingKey.toastDuration) == nil
      ? setting.defaultValue : setting.clamped(defaults.double(forKey: AppSettingKey.toastDuration))
    return .milliseconds(Int((seconds * 1_000).rounded()))
  }

  func show(
    _ message: String, systemImage: String = "checkmark", action: Toast.Action? = nil,
    secondAction: Toast.Action? = nil, duration: Duration? = nil
  ) {
    current = Toast(
      message: message, systemImage: systemImage, action: action, secondAction: secondAction, duration: duration)
    scheduleDismiss()
  }

  func dismiss() {
    dismissTask?.cancel()
    dismissTask = nil
    current = nil
  }

  func performAction(second: Bool = false) {
    let action = second ? current?.secondAction : current?.action
    dismiss()
    action?.perform()
  }

  func setHovering(_ hovering: Bool) {
    isHovering = hovering
    scheduleDismiss()
  }

  /// Only one waiting task. If replaced by another toast meanwhile, that one isn't closed.
  private func scheduleDismiss() {
    dismissTask?.cancel()
    dismissTask = nil
    guard !isHovering, let id = current?.id else { return }
    let duration = fixedDuration ?? current?.duration ?? Self.storedDuration()
    dismissTask = Task {
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled, current?.id == id else { return }
      current = nil
      dismissTask = nil
    }
  }
}

/// Layer over the editor. The top-right position follows the safe area (below the toolbar), so window size and toolbar height aren't hard-coded.
struct ToastOverlay: View {
  let center: ToastCenter
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if let toast = center.current {
        ToastView(
          toast: toast, onAction: { center.performAction() }, onSecondAction: { center.performAction(second: true) })
          .onHover { center.setHovering($0) }
          .id(toast.id)
          .transition(.opacity.combined(with: .offset(y: -6)))
      }
    }
    .padding(.top, ToastView.edgeInset)
    .padding(.trailing, ToastView.edgeInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    // 150 ms (DESIGN.md ch.6). With reduce motion on, appears and disappears instantly without animation.
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: center.current?.id)
  }
}

/// Pill shape: gray icon + short text (+ text button). Background is the system default glass; no color applied.
struct ToastView: View {
  static let edgeInset: CGFloat = 12

  let toast: Toast
  var onAction: () -> Void = {}
  var onSecondAction: () -> Void = {}

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: toast.systemImage)
        .font(.system(size: 10, weight: .semibold))
      Text(toast.message)
      if let action = toast.action {
        Text("·")
        Button(action.title, action: onAction)
          .buttonStyle(.plain)
          .foregroundStyle(Color.ink)
      }
      if let action = toast.secondAction {
        Text("·")
        Button(action.title, action: onSecondAction)
          .buttonStyle(.plain)
          .foregroundStyle(Color.ink)
      }
    }
    .font(.system(size: 11))
    .foregroundStyle(Color.inkMuted)
    .lineLimit(1)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .glassEffect(.regular, in: .capsule)
  }
}

#Preview("토스트") {
  VStack(alignment: .trailing, spacing: 12) {
    ToastView(toast: Toast(message: "저장했어요"))
    ToastView(toast: Toast(message: "스냅샷을 찍었어요", action: .init(title: "메모 달기") {}))
  }
  .padding(24)
  .background(Color.paper)
}
