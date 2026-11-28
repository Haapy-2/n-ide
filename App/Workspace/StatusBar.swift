import NovelCore
import Observation
import SwiftUI

/// Status bar at the bottom of the editor (DESIGN.md ch.4): count · goal progress · save state.
/// Edges align with the body width. It floats over the body, so when visible a paper-colored background hides text below,
/// and when hidden the background goes too so the body shows. Save failure indicators don't hide, so the background stays then.
struct StatusBar: View {
  let counter: CharacterCounter
  let autosaver: EpisodeAutosaver
  let fade: StatusBarFade
  let goal: Int
  /// Same body width as the editor (setting value).
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
    // When hidden, the body below stays clickable.
    .allowsHitTesting(isCovering)
    // Fades over 150 ms (DESIGN.md ch.6). With reduce motion on, changes instantly.
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: fade.isHidden)
  }

  private var isCovering: Bool {
    switch autosaver.status {
    case .failed, .retrying: true
    default: autosaver.restoreNotice != nil || !fade.isHidden
    }
  }

  private func failureExplanation(_ failure: EpisodeAutosaver.Failure) -> String {
    let safety =
      failure.isBackedUp
      ? "원고는 앱 메모리에 있고, 앱이 꺼져도 다음에 열 때 되살릴 수 있게 작품 밖에 따로 백업해 두었어요."
      : "원고는 앱 메모리에 있어요. 앱을 끄기 전에 다시 시도하거나 다른 곳에 저장해 주세요."
    return failure.detail + "\n\n" + safety
  }

  /// Usually empty. Failure indicators don't fade.
  @ViewBuilder
  private var saveStatus: some View {
    switch autosaver.status {
    case .failed(let failure):
      HStack(spacing: 4) {
        Button("저장 실패 · \(failure.label)") { showsFailureReason = true }
          .buttonStyle(.plain)
          .foregroundStyle(Color.error)
          .help("까닭 보기")
          .popover(isPresented: $showsFailureReason) {
            Text(failureExplanation(failure))
              .font(.system(size: 12))
              .frame(maxWidth: 320, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
              .padding(12)
          }
        Text("·")
        Button("다시 시도") { Task { await autosaver.flush() } }
          .buttonStyle(.plain)
          .foregroundStyle(Color.ink)
        Text("·")
        Button("다른 곳에 저장…") {
          if SystemDialogs.exportUnsaved(autosaver.unsavedManuscripts()) { autosaver.markRescued() }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.ink)
        .help("저장하지 못한 원고를 고른 폴더에 .md로 저장")
      }
    case .retrying:
      Text("저장 실패 · 다시 시도 중")
        .foregroundStyle(Color.error)
    case .saving where autosaver.showsSavingIndicator:
      Text("저장 중…")
        .opacity(fade.isHidden ? 0 : 1)
    default:
      if let notice = autosaver.restoreNotice {
        HStack(spacing: 4) {
          Text(notice)
          Text("·")
          Button("취소") { autosaver.undoRestore() }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            .help("되돌리기 전으로 (⌘Z)")
        }
      }
    }
  }
}

/// Goal progress: next to `97%`, a small ring, a full circle (pie) or a thin bar. Filled part accent, remainder a faint gray track.
/// Drawing the track in `rule` color makes it nearly paper-colored in dark mode, so the remainder disappears.
/// Past 100% the number keeps rising and the shape stays full.
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
            // Fills clockwise from 12 o'clock. Round caps would cover the gap when little remains (like 97%), so caps are square.
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

/// A sector filled clockwise from 12 o'clock by `fraction`.
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

/// Hiding the status bar:
/// - While typing: visible by default. With "hide", it disappears 1 s after typing starts and reappears after input pauses 1.5 s.
/// - While idle: by default it disappears 10 s after the last input/mouse movement. "Always visible" can be chosen.
/// - Even hidden, moving the mouse or typing again brings it back (if hide-while-typing is chosen, it stays hidden while typing).
/// SwiftUI state isn't changed per keystroke (docs/PERFORMANCE.md ch.2). `isHidden` changes only when visibility actually changes;
/// otherwise only unobserved values (times) are recorded. Only one waiting task exists.
@MainActor
@Observable
final class StatusBarFade {
  private(set) var isHidden = false

  /// Setting values. Call `reconsider()` after changing.
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

  func noteInput() {
    let now = ContinuousClock.now
    lastInput = now
    lastActivity = now
    if burstStart == nil { burstStart = now }
    watch()
  }

  /// On mouse movement. Continued typing restarts the decision.
  func show() {
    burstStart = nil
    lastActivity = .now
    if isHidden { isHidden = false }
    watch()
  }

  /// On settings change: drop the waiting task and decide again with the current settings.
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

  /// Decide whether to show or hide now, and return when to decide again. nil means nothing more to wait for.
  private func step() -> ContinuousClock.Instant? {
    let now = ContinuousClock.now
    if let start = burstStart {
      if now - lastInput < showAfter {
        // Typing
        let hide = hidesWhileTyping && now - start >= hideAfter
        setHidden(hide)
        let showCheck = lastInput + showAfter
        return hidesWhileTyping && !hide ? min(start + hideAfter, showCheck) : showCheck
      }
      burstStart = nil
    }
    // Idle
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
