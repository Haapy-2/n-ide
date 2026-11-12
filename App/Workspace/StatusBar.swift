import NovelCore
import Observation
import SwiftUI

/// 편집 영역 맨 아래 상태 줄 (DESIGN.md 4장): 글자 수 · 목표 진행률 · 저장 상태.
/// 좌우 끝을 본문 폭에 맞춘다. 배경 없이 종이 위에 바로 글자.
struct StatusBar: View {
  let counter: CharacterCounter
  let autosaver: EpisodeAutosaver
  let fade: StatusBarFade
  let goal: Int
  /// 편집기와 같은 본문 폭(10단계에서 설정 값으로 바뀐다).
  var textWidth: CGFloat = EditorStyle().textWidth
  @AppStorage(AppSettingKey.characterCountDisplay) private var display: CharacterCountDisplay = .both
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showsFailureReason = false

  var body: some View {
    HStack(spacing: 16) {
      Group {
        if let count = counter.current {
          Text(display.text(for: count))
        }
        Spacer(minLength: 0)
        if let count = counter.current, goal > 0 {
          GoalProgress(value: count.value(for: basis), goal: goal)
        }
      }
      .opacity(fade.isHidden ? 0 : 1)
      saveStatus
    }
    .font(.system(size: 11).monospacedDigit())
    .foregroundStyle(Color.inkMuted)
    .frame(maxWidth: textWidth)
    .frame(height: 28)
    .padding(.horizontal, EditorStyle.minimumSideInset)
    .frame(maxWidth: .infinity)
    // 흐려짐은 150ms(DESIGN.md 6장). 동작 줄이기가 켜져 있으면 바로 바뀐다.
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: fade.isHidden)
  }

  /// 평소엔 비어 있다. 실패 표시는 흐려지지 않는다.
  @ViewBuilder
  private var saveStatus: some View {
    switch autosaver.status {
    case .failed(let message):
      Button("저장 실패 · 원고는 메모리에 있음") { showsFailureReason = true }
        .buttonStyle(.plain)
        .foregroundStyle(Color.error)
        .popover(isPresented: $showsFailureReason) {
          Text(message)
            .font(.system(size: 12))
            .frame(maxWidth: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
        }
    case .retrying:
      Text("저장 실패 · 다시 시도 중")
        .foregroundStyle(Color.error)
    case .saving where autosaver.showsSavingIndicator:
      Text("저장 중…")
        .opacity(fade.isHidden ? 0 : 1)
    default:
      EmptyView()
    }
  }
}

/// `24%`와 그 아래 2pt 진행 막대(accent). 100%를 넘으면 숫자는 그대로, 막대는 가득.
private struct GoalProgress: View {
  let value: Int
  let goal: Int
  private static let barWidth: CGFloat = 36

  var body: some View {
    let fraction = Double(value) / Double(goal)
    VStack(alignment: .trailing, spacing: 2) {
      Text("\(Int(fraction * 100))%")
      ZStack(alignment: .leading) {
        Rectangle().fill(Color.rule)
        Rectangle().fill(Color.accent).frame(width: Self.barWidth * min(fraction, 1))
      }
      .frame(width: Self.barWidth, height: 2)
    }
    .help("목표 \(goal.formatted())자")
  }
}

/// 상태 줄 흐려짐: 타이핑을 시작하고 1초가 지나면 사라지고, 입력이 1.5초 멈추거나 마우스를 움직이면 나타난다.
/// 키 입력마다 SwiftUI 상태를 바꾸지 않는다(docs/PERFORMANCE.md 2장). `isHidden`은 한 번 타이핑하는 동안
/// 숨길 때와 다시 보일 때 두 번만 바뀌고, 나머지는 관찰하지 않는 값(시각)만 적는다.
@MainActor
@Observable
final class StatusBarFade {
  private(set) var isHidden = false

  @ObservationIgnored private var burstStart: ContinuousClock.Instant?
  @ObservationIgnored private var lastInput = ContinuousClock.now
  @ObservationIgnored private var watcher: Task<Void, Never>?
  private let hideAfter: Duration
  private let showAfter: Duration

  init(hideAfter: Duration = .seconds(1), showAfter: Duration = .milliseconds(1_500)) {
    self.hideAfter = hideAfter
    self.showAfter = showAfter
  }

  /// 편집기에서 글을 고칠 때마다.
  func noteInput() {
    let now = ContinuousClock.now
    lastInput = now
    if burstStart == nil { burstStart = now }
    guard watcher == nil else { return }
    watcher = Task {
      while let start = burstStart {
        let now = ContinuousClock.now
        if now - lastInput >= showAfter {
          burstStart = nil
          if isHidden { isHidden = false }
          break
        }
        if !isHidden, now - start >= hideAfter { isHidden = true }
        let next = isHidden ? lastInput + showAfter : min(start + hideAfter, lastInput + showAfter)
        try? await Task.sleep(until: next, clock: .continuous)
      }
      watcher = nil
    }
  }

  /// 마우스를 움직였을 때. 이어서 타이핑하면 다시 1초 뒤에 사라진다.
  func show() {
    burstStart = nil
    if isHidden { isHidden = false }
  }
}
