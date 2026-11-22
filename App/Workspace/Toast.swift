import SwiftUI

/// 편집 영역 오른쪽 위에 잠깐 떴다 사라지는 작은 알림.
/// 시스템 알림이 아니라 창 안에만 뜬다. 편집기 초점·선택·한글 조합은 건드리지 않는다.
struct Toast: Identifiable {
  /// 토스트 오른쪽의 글자 버튼(예: "메모 달기"). 누르면 토스트가 닫힌다.
  struct Action {
    let title: String
    let perform: () -> Void
  }

  let id = UUID()
  let message: String
  /// 회색 단색 SF Symbol 이름.
  var systemImage = "checkmark"
  var action: Action?
  /// 두 번째 글자 버튼(전체 바꾸기 뒤 `바꾼 곳 보기 · 되돌리기`)
  var secondAction: Action?
  /// nil이면 설정의 알림 유지 시간. 되돌리기 버튼이 있는 큰 작업은 길게 둔다.
  var duration: Duration?
}

/// 창 하나에 하나. 한 번에 하나만 보이고, 새 알림은 이전 것을 바로 바꾼다(쌓이지 않음).
/// 설정 "알림 유지 시간"(기본 2초) 뒤 사라지고, 마우스가 올라가 있는 동안은 기다렸다가 내려가면 다시 센다.
@MainActor
@Observable
final class ToastCenter {
  private(set) var current: Toast?

  @ObservationIgnored private var isHovering = false
  @ObservationIgnored private var dismissTask: Task<Void, Never>?
  /// nil이면 띄울 때마다 설정 값을 읽는다(바꾸면 다음 알림부터 바로). 테스트는 짧은 값을 넣는다.
  private let fixedDuration: Duration?

  init(duration: Duration? = nil) {
    fixedDuration = duration
  }

  /// 설정 값을 0.5~5초, 0.5 단위로 맞춰 읽는다. 없으면 기본 2초.
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

  /// 기다리는 작업은 하나만 둔다. 기다리는 사이 다른 토스트로 바뀌었으면 그것은 닫지 않는다.
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

/// 편집 영역 위에 얹는 층. 오른쪽 위 자리는 안전 영역(툴바 아래)을 따라가므로 창 크기·툴바 높이를 숫자로 박지 않는다.
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
    // 150ms(DESIGN.md 6장). 동작 줄이기가 켜져 있으면 움직임 없이 바로 나타나고 사라진다.
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: center.current?.id)
  }
}

/// 알약 모양: 회색 아이콘 + 짧은 문구(+ 글자 버튼). 바탕은 시스템 기본 유리, 색은 입히지 않는다.
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
