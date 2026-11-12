import NovelCore
import Observation
import SwiftUI

/// 편집 영역 맨 아래 상태 줄 (DESIGN.md 4장): 글자 수 · 목표 진행률 · 저장 상태.
/// 좌우 끝을 본문 폭에 맞춘다. 본문 위에 겹쳐 뜨므로 보일 때는 종이색 바탕으로 아래 글을 가리고,
/// 숨을 때는 바탕도 함께 사라져 본문이 보인다. 저장 실패 표시는 숨지 않으므로 그때는 바탕도 남긴다.
struct StatusBar: View {
  let counter: CharacterCounter
  let autosaver: EpisodeAutosaver
  let fade: StatusBarFade
  let goal: Int
  /// 편집기와 같은 본문 폭(설정 값).
  var textWidth: CGFloat = EditorStyle().textWidth
  @AppStorage(AppSettingKey.characterCountDisplay) private var display: CharacterCountDisplay = .both
  @AppStorage(AppSettingKey.characterCountGoalBasis) private var basis: CharacterCountBasis = .withSpaces
  @AppStorage(AppSettingKey.goalProgressStyle) private var progressStyle: GoalProgressStyle = .ring
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
          GoalProgress(value: count.value(for: basis), goal: goal, style: progressStyle)
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
    .background(Color.paper.opacity(isCovering ? 1 : 0))
    // 숨어 있을 때는 아래 본문을 클릭할 수 있게 한다.
    .allowsHitTesting(isCovering)
    // 흐려짐은 150ms(DESIGN.md 6장). 동작 줄이기가 켜져 있으면 바로 바뀐다.
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: fade.isHidden)
  }

  private var isCovering: Bool {
    switch autosaver.status {
    case .failed, .retrying: true
    default: !fade.isHidden
    }
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

/// 목표 진행률: `97%` 옆에 작은 고리, 꽉 찬 원(파이) 또는 가는 막대. 채운 부분은 accent, 남은 부분은 흐린 회색 트랙.
/// 트랙을 `rule` 색으로 그리면 다크 모드에서 종이와 거의 같아 남은 부분이 안 보였다(2026-11-12 사용자 지적).
/// 100%를 넘으면 숫자는 그대로 올라가고 모양은 가득 찬 채로 있다.
struct GoalProgress: View {
  let value: Int
  let goal: Int
  let style: GoalProgressStyle

  private static let ringSize: CGFloat = 14
  private static let ringLine: CGFloat = 2
  private static let barWidth: CGFloat = 80
  private static let barHeight: CGFloat = 4
  private static let trackOpacity = 0.35

  var body: some View {
    let fraction = min(Double(value) / Double(goal), 1)
    HStack(spacing: 6) {
      Text("\(Int(Double(value) / Double(goal) * 100))%")
      switch style {
      case .ring:
        ZStack {
          Circle().stroke(Color.inkMuted.opacity(Self.trackOpacity), lineWidth: Self.ringLine)
          Circle()
            .trim(from: 0, to: fraction)
            .stroke(Color.accent, style: StrokeStyle(lineWidth: Self.ringLine, lineCap: .butt))
            // 12시 방향에서 시계 방향으로 채운다. 끝을 둥글게 하면 97%처럼 조금 남았을 때 틈이 덮여 안 보여서 각지게.
            .rotationEffect(.degrees(-90))
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
      case .pie:
        ZStack {
          Circle().fill(Color.inkMuted.opacity(Self.trackOpacity))
          PieSlice(fraction: fraction).fill(Color.accent)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
      case .bar:
        ZStack(alignment: .leading) {
          Capsule().fill(Color.inkMuted.opacity(Self.trackOpacity))
          Capsule().fill(Color.accent).frame(width: Self.barWidth * fraction)
        }
        .frame(width: Self.barWidth, height: Self.barHeight)
      }
    }
    .help(helpText)
  }

  private var helpText: String {
    let left = goal - value
    return left > 0 ? "목표 \(goal.formatted())자 · \(left.formatted())자 남음" : "목표 \(goal.formatted())자 달성"
  }
}

/// 12시 방향에서 시계 방향으로 `fraction`만큼 채운 부채꼴.
private nonisolated struct PieSlice: Shape {
  let fraction: Double

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard fraction > 0 else { return path }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    path.move(to: center)
    path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
    path.closeSubpath()
    return path
  }
}

/// 상태 줄 숨기기 (2026-11-12 사용자 요청, 설정 창 "화면" 묶음):
/// - 타이핑 중: 기본은 계속 보인다. "숨기기"를 고르면 치기 시작하고 1초 뒤 사라졌다가 입력이 1.5초 멈추면 나타난다.
/// - 쉬고 있을 때: 기본은 마지막 입력·마우스 움직임 10초 뒤에 사라진다. "계속 보이기"를 고를 수 있다.
/// - 숨어 있어도 마우스를 움직이거나 다시 치면 나타난다(타이핑 중 숨기기를 골랐으면 칠 때는 그대로 숨김).
/// 키 입력마다 SwiftUI 상태를 바꾸지 않는다(docs/PERFORMANCE.md 2장). `isHidden`은 보이기·숨기기가 실제로 바뀔 때만 바뀌고,
/// 나머지는 관찰하지 않는 값(시각)만 적는다. 기다리는 작업은 하나만 둔다.
@MainActor
@Observable
final class StatusBarFade {
  private(set) var isHidden = false

  /// 설정 값. 바꾼 뒤에는 `reconsider()`.
  @ObservationIgnored var hidesWhileTyping = false
  @ObservationIgnored var hidesWhenIdle = true

  @ObservationIgnored private var burstStart: ContinuousClock.Instant?
  @ObservationIgnored private var lastInput = ContinuousClock.now
  @ObservationIgnored private var lastActivity = ContinuousClock.now
  @ObservationIgnored private var watcher: Task<Void, Never>?
  private let hideAfter: Duration
  private let showAfter: Duration
  private let idleAfter: Duration

  init(hideAfter: Duration = .seconds(1), showAfter: Duration = .milliseconds(1_500), idleAfter: Duration = .seconds(10)) {
    self.hideAfter = hideAfter
    self.showAfter = showAfter
    self.idleAfter = idleAfter
  }

  /// 편집기에서 글을 고칠 때마다.
  func noteInput() {
    let now = ContinuousClock.now
    lastInput = now
    lastActivity = now
    if burstStart == nil { burstStart = now }
    watch()
  }

  /// 마우스를 움직였을 때. 이어서 타이핑하면 처음부터 다시 판단한다.
  func show() {
    burstStart = nil
    lastActivity = .now
    if isHidden { isHidden = false }
    watch()
  }

  /// 설정이 바뀌었을 때: 기다리던 작업을 버리고 지금 설정으로 다시 판단한다.
  func reconsider() {
    watcher?.cancel()
    watcher = nil
    watch()
  }

  private func watch() {
    guard watcher == nil else { return }
    watcher = Task {
      while let next = step() {
        try? await Task.sleep(until: next, clock: .continuous)
        if Task.isCancelled { return }
      }
      watcher = nil
    }
  }

  /// 지금 보일지 숨길지 정하고, 다음에 다시 판단할 시각을 돌려준다. nil이면 더 기다릴 일이 없다.
  private func step() -> ContinuousClock.Instant? {
    let now = ContinuousClock.now
    if let start = burstStart {
      if now - lastInput < showAfter {
        // 타이핑 중
        let hide = hidesWhileTyping && now - start >= hideAfter
        setHidden(hide)
        let showCheck = lastInput + showAfter
        return hidesWhileTyping && !hide ? min(start + hideAfter, showCheck) : showCheck
      }
      burstStart = nil
    }
    // 쉬는 중
    guard hidesWhenIdle else {
      setHidden(false)
      return nil
    }
    let due = lastActivity + idleAfter
    setHidden(now >= due)
    return now >= due ? nil : due
  }

  private func setHidden(_ hidden: Bool) {
    if isHidden != hidden { isHidden = hidden }
  }
}

// Xcode 캔버스(⌥⌘↩)에서 두 모양을 바로 비교할 수 있다.
#Preview("목표 진행률") {
  VStack(alignment: .trailing, spacing: 12) {
    ForEach(GoalProgressStyle.allCases, id: \.self) { style in
      ForEach([4_850, 2_400, 5_600], id: \.self) { value in
        GoalProgress(value: value, goal: 5_000, style: style)
      }
    }
  }
  .font(.system(size: 11).monospacedDigit())
  .foregroundStyle(Color.inkMuted)
  .padding(24)
  .background(Color.paper)
}
