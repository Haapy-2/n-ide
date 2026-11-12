import AppKit
import NovelCore
import Observation

/// 지금 회차의 글자 수 (SPEC 7장 3번, 8장).
/// - 키 입력마다 세지 않는다. 입력이 잠깐(0.3초) 멈추면 본문을 한 번 복사해 메인 스레드 밖에서 전체를 센다.
///   측정해 보니 5,000자 0.3ms, 10만 자 20ms라 증분 계산은 만들지 않았다(docs/log/log26-11-12.md).
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
  @ObservationIgnored private var lastEdit = ContinuousClock.now
  @ObservationIgnored private var waiting: Task<Void, Never>?
  /// 회차별로 가장 나중에 시작한 계산 번호. 뒤에서 늦게 끝난 옛 계산이 새 값을 덮지 못하게 한다.
  @ObservationIgnored private var latest: [EpisodeID: Int] = [:]
  @ObservationIgnored private var generation = 0
  private let delay: Duration

  init(delay: Duration = .milliseconds(300)) {
    self.delay = delay
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
      recount()
    }
    episodeID = id
    if current != known { current = known }
    count(text, for: id)
  }

  private func textDidChange() {
    lastEdit = .now
    // 키마다 작업을 새로 만들지 않는다. 기다리는 작업 하나가 마지막 입력 시각을 보고 멈춤을 판단한다.
    guard waiting == nil else { return }
    waiting = Task {
      while true {
        let due = lastEdit + delay
        guard ContinuousClock.now < due else { break }
        try? await Task.sleep(until: due, clock: .continuous)
        if Task.isCancelled { return }
      }
      waiting = nil
      recount()
    }
  }

  private func recount() {
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
