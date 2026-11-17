import NovelCore

/// 스냅샷을 찍는 때 (11b, PLAN 10장 3번). 자동 저장기(`EpisodeAutosaver`)가 갖고 있고 본문은 그쪽이 건넨다.
/// - 자동: 설정한 간격마다, 지금 회차를 그사이 고쳤을 때만.
/// - 떠날 때: 회차 전환·창 닫기·앱 종료. 자동을 꺼도 늘 찍는다(결정 16). 이번에 고치지 않은 회차는 찍지 않는다
///   (훑어보기만 한 회차마다 스냅샷이 생기지 않게).
/// - 직접(⌃⌘S): 고치지 않았어도 찍는다.
/// 자동·떠날 때는 마지막 스냅샷과 같으면 건너뛰고, 찍은 뒤 보관 개수로 정리한다.
/// 쓰기는 메인 스레드 밖에서 한 줄로 차례대로 한다(앞 것이 끝나야 "마지막과 같은지"를 바르게 본다).
@MainActor
final class EpisodeSnapshotter {
  struct Settings: Equatable {
    var autoEnabled = true
    var interval: Duration = .seconds(30 * 60)
    /// `auto`·`leave`를 회차마다 몇 개까지 남길지
    var retention = 50

    static let intervalChoices = [5, 10, 15, 30, 60]
    static let retentionRange = 10...100

    /// 설정 창 값(분, 개수)을 고를 수 있는 값으로 맞춘다. 손으로 고친 UserDefaults 값도 여기서 걸러진다.
    init(autoEnabled: Bool = true, minutes: Int = 30, retention: Int = 50) {
      self.autoEnabled = autoEnabled
      let minutes = Self.intervalChoices.contains(minutes) ? minutes : 30
      interval = .seconds(minutes * 60)
      let clamped = min(max(retention, Self.retentionRange.lowerBound), Self.retentionRange.upperBound)
      self.retention = clamped / 10 * 10
    }
  }

  var settings = Settings() {
    didSet {
      if settings.autoEnabled != oldValue.autoEnabled || settings.interval != oldValue.interval { restartTimer() }
    }
  }

  /// 자동 스냅샷 때 지금 회차와 그 본문을 꺼내 준다. 본문은 고친 경우에만 꺼낸다(복사를 아끼려고).
  var currentEpisode: () -> EpisodeID? = { nil }
  var currentText: () -> String? = { nil }

  private let store: ProjectStore
  /// 마지막 스냅샷 뒤에 고친 회차
  private var edited: Set<EpisodeID> = []
  private var tail: Task<Void, Never>?
  /// 아직 안 끝난 쓰기 수
  private var pending = 0
  private var timer: Task<Void, Never>?

  init(store: ProjectStore) {
    self.store = store
    restartTimer()
  }

  /// 찍어야 할 것이 남았는지(앱 종료 때 기다릴지 정한다).
  var hasPendingWork: Bool { !edited.isEmpty || pending > 0 }

  func noteEdit(_ id: EpisodeID) {
    edited.insert(id)
  }

  /// 회차를 떠날 때. 이번에 고쳤으면 본문을 받아 `leave`로 남긴다.
  func leave(_ id: EpisodeID, text: () -> String?) {
    // 본문을 못 받으면(편집기가 이미 없음) 표시를 남겨 둔다. 앱 종료 때 "찍을 것이 남음"으로 보이게.
    guard edited.contains(id), let text = text() else { return }
    edited.remove(id)
    enqueue(text, id, .leave)
  }

  /// 직접 찍기. 다 쓸 때까지 기다리고 찍은 스냅샷을 돌려준다.
  /// `skipIfUnchanged`면 마지막 스냅샷과 같을 때 찍지 않고 nil(저장하면서 스냅샷 찍기: ⌘S를 자주 눌러도 쌓이지 않게).
  func takeManual(_ id: EpisodeID, text: String, skipIfUnchanged: Bool = false) async throws -> Snapshot? {
    edited.remove(id)
    return try await enqueue(text, id, .manual, skipIfSame: skipIfUnchanged).value
  }

  /// 되돌리기 직전 지금 본문을 `restore`로 남긴다(11e). 같은 내용이어도 늘 찍는다: 메모로 "언제 무엇으로 되돌렸나"를 남기려고.
  func takeRestore(_ id: EpisodeID, text: String, memo: String) async throws -> Snapshot? {
    try await enqueue(text, id, .restore, memo: memo).value
  }

  /// 휴지통으로 보낸 회차는 더 찍지 않는다.
  func forget(_ id: EpisodeID) {
    edited.remove(id)
  }

  /// 지금까지 맡은 쓰기가 다 끝날 때까지 기다린다.
  func waitForWrites() async {
    while pending > 0, let task = tail {
      await task.value
    }
  }

  /// 간격마다 부른다. 테스트에서도 직접 부른다.
  func autoTick() {
    guard settings.autoEnabled, let id = currentEpisode(), edited.contains(id), let text = currentText() else { return }
    edited.remove(id)
    enqueue(text, id, .auto)
  }

  private func restartTimer() {
    timer?.cancel()
    guard settings.autoEnabled else {
      timer = nil
      return
    }
    let interval = settings.interval
    timer = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled, let self else { return }
        self.autoTick()
      }
    }
  }

  @discardableResult
  private func enqueue(
    _ text: String, _ id: EpisodeID, _ kind: SnapshotKind, memo: String? = nil, skipIfSame: Bool = false
  ) -> Task<Snapshot?, any Error> {
    let previous = tail
    let retention = settings.retention
    let task = Task<Snapshot?, any Error> {
      await previous?.value
      defer { pending -= 1 }
      do {
        return try await write(text, id, kind, memo: memo, skipIfSame: skipIfSame, retention: retention)
      } catch {
        // 못 찍었으면(디스크가 꽉 찼을 때 등) "고친 회차"로 되돌린다. 아직 그 회차를 보고 있으면 다음 간격이나 떠날 때 다시 찍는다.
        if kind.isPrunable { edited.insert(id) }
        throw error
      }
    }
    pending += 1
    tail = Task { _ = await task.result }
    return task
  }

  private func write(
    _ text: String, _ id: EpisodeID, _ kind: SnapshotKind, memo: String?, skipIfSame: Bool, retention: Int
  ) async throws -> Snapshot? {
    let store = store
    return try await Task.detached {
      // 자동·떠날 때만 마지막과 같으면 건너뛴다. 직접·복원 전은 사용자가 그 순간을 남기려는 것이라 늘 찍는다
      // (저장하면서 찍는 직접 찍기만 예외로 건너뛴다).
      let snapshot = try store.writeSnapshot(
        text, episode: id, kind: kind, memo: memo, skipIfSameAsLatest: kind.isPrunable || skipIfSame)
      // 정리가 실패해도 방금 찍은 것은 남았으니 실패로 치지 않는다. 다음에 찍을 때 다시 정리한다.
      if kind.isPrunable { _ = try? store.pruneSnapshots(of: id, keeping: retention) }
      return snapshot
    }.value
  }
}
