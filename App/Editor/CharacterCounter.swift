import AppKit
import NovelCore
import Observation

/// 지금 회차의 글자 수 (SPEC 7장 3번, 8장).
/// - 고치기 시작하면 `interval`(설정의 "글자 수 갱신", 기본 0.2초) 뒤에 본문을 한 번 복사해 메인 스레드 밖에서 전체를 센다.
///   그사이 들어온 입력은 그 한 번에 묶인다. 치는 동안에도 `interval`마다 숫자가 바뀐다.
///   `interval`이 0(실시간)이면 그 차례의 입력을 마치자마자 센다.
///   측정해 보니 5,000자 0.3ms, 10만 자 10ms라 증분 계산은 만들지 않았다(docs/log/log26-11-12.md).
/// - 텍스트 저장소는 읽기만 한다. 한글 조합 중에 세어도 조합이 끊기지 않는다(조합 중인 글자도 한 글자로 센다).
/// - 입력뿐 아니라 실행 취소, 외부 변경으로 다시 읽기도 텍스트 저장소 알림으로 함께 잡는다.
@MainActor
@Observable
final class CharacterCounter {
  /// 지금 회차의 글자 수. 상태 줄이 본다. 값이 바뀔 때만 바꿔서 상태 줄이 쓸데없이 다시 그려지지 않게 한다.
  private(set) var current: CharacterCount?

  /// 센 결과를 받는 곳(회차 목록에 기록 → 사이드바, project.json).
  @ObservationIgnored var onCount: (EpisodeID, CharacterCount) -> Void = { _, _ in }
  @ObservationIgnored private(set) var episodeID: EpisodeID?
  @ObservationIgnored private weak var textView: NSTextView?
  @ObservationIgnored private var observer: NSObjectProtocol?
  @ObservationIgnored private var waiting: Task<Void, Never>?
  /// 회차별로 가장 나중에 시작한 계산 번호. 뒤에서 늦게 끝난 옛 계산이 새 값을 덮지 못하게 한다.
  @ObservationIgnored private var latest: [EpisodeID: Int] = [:]
  @ObservationIgnored private var generation = 0
  /// 고친 뒤 세기까지 기다리는 시간. 설정 창에서 바꾼다.
  @ObservationIgnored var interval: Duration

  init(interval: Duration = .milliseconds(200)) {
    self.interval = interval
  }

  func attach(_ textView: NSTextView) {
    guard self.textView !== textView else { return }
    if let observer { NotificationCenter.default.removeObserver(observer) }
    self.textView = textView
    // 텍스트 저장소를 고친 그 자리(메인 스레드)에서 바로 불린다. 여기서는 시각만 적는다.
    observer = NotificationCenter.default.addObserver(
      forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
    ) { [weak self] notification in
      let charactersChanged = (notification.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) ?? false
      guard charactersChanged else { return }
      MainActor.assumeIsolated { self?.textDidChange() }
    }
  }

  /// 회차를 열 때. `text`는 막 읽은 본문, `known`은 project.json에 남아 있던 값(세는 동안 잠깐 보여준다).
  func begin(episode id: EpisodeID, text: String, known: CharacterCount?) {
    // 떠나는 회차에 아직 세지 않은 입력이 있으면 편집기에 옛 본문이 남아 있는 지금 센다.
    if waiting != nil {
      waiting?.cancel()
      waiting = nil
      recountNow()
    }
    episodeID = id
    if current != known { current = known }
    count(text, for: id)
  }

  private func textDidChange() {
    // 키마다 작업을 새로 만들지 않는다. 기다리는 작업이 이미 있으면 이번 입력도 그 작업이 함께 센다.
    // 텍스트 저장소를 고치는 중(이 알림 안)에는 본문을 꺼내지 않고, 적어도 다음 차례로 미룬다.
    guard waiting == nil else { return }
    let interval = interval
    waiting = Task {
      if interval > .zero { try? await Task.sleep(for: interval) }
      if Task.isCancelled { return }
      waiting = nil
      recountNow()
    }
  }

  /// 편집기의 지금 본문으로 바로 센다(복사만 메인 스레드, 세기는 밖에서). 성능 측정도 이것을 부른다.
  func recountNow() {
    guard let id = episodeID, let textView else { return }
    count(textView.string, for: id)
  }

  private func count(_ text: String, for id: EpisodeID) {
    generation += 1
    let number = generation
    latest[id] = number
    Task {
      let result = await Task.detached { CharacterCount(counting: text) }.value
      guard latest[id] == number else { return }
      latest[id] = nil
      if id == episodeID, current != result { current = result }
      onCount(id, result)
    }
  }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}
