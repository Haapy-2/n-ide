import AppKit
import NovelCore
import Observation

/// 회차 자동 저장 (SPEC 6장, 7장 4번).
/// - 입력이 멈추고 1초 뒤 저장한다. 회차 전환·창 비활성·앱 종료 때는 바로 저장한다(`flush`).
/// - 실제 쓰기는 `SaveQueue`가 순서대로 처리하고 실패하면 재시도한다.
/// - 끝내 실패하면 그 회차 본문을 메모리(`unsaved`)에 들고 있다가, 그 회차를 다시 열 때 디스크 대신 이것을 보여준다.
/// - 텍스트 저장소는 읽기만 한다. 그래서 한글 조합 중에 저장해도 조합이 끊기지 않는다.
@MainActor
@Observable
final class EpisodeAutosaver {
  enum Status: Equatable {
    case idle
    case saving
    case failed(String)
  }

  private(set) var status: Status = .idle
  /// 저장이 0.5초 넘게 걸릴 때만 켜진다. 평소 저장은 화면에 아무것도 띄우지 않는다(DESIGN.md 4장).
  private(set) var showsSavingIndicator = false

  let store: ProjectStore
  private let queue: SaveQueue
  private let delay: Duration
  @ObservationIgnored private weak var textView: ManuscriptTextView?
  @ObservationIgnored private(set) var episodeID: EpisodeID?
  /// 회차별 변경 번호. 입력할 때마다 1씩 오른다.
  @ObservationIgnored private var changes: [EpisodeID: Int] = [:]
  @ObservationIgnored private var savedChanges: [EpisodeID: Int] = [:]
  /// 저장에 실패한 회차의 본문.
  @ObservationIgnored private var unsaved: [EpisodeID: String] = [:]
  /// 파일에 쓰는 중인 회차의 본문.
  @ObservationIgnored private var inFlight: [EpisodeID: String] = [:]
  @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var pendingSave: Task<Void, Never>?

  init(store: ProjectStore, queue: SaveQueue = SaveQueue(), delay: Duration = .seconds(1)) {
    self.store = store
    self.queue = queue
    self.delay = delay
    AutosaverRegistry.shared.register(self)
  }

  /// 저장 안 된 변경이 있는지 (지금 회차 또는 저장에 실패한 회차).
  var hasUnsavedChanges: Bool {
    if let episodeID, isDirty(episodeID) { return true }
    return !unsaved.isEmpty || !running.isEmpty
  }

  func attach(_ textView: ManuscriptTextView) {
    self.textView = textView
  }

  /// 회차를 열 때 디스크 대신 보여줄 본문: 저장에 실패해 메모리에 남은 것, 또는 아직 쓰는 중인 것. 없으면 nil.
  /// (빠르게 A→B→A로 돌아왔을 때 A 저장이 끝나기 전 디스크의 옛 본문을 읽지 않기 위해서다.)
  func pendingText(for id: EpisodeID) -> String? {
    unsaved[id] ?? inFlight[id]
  }

  /// 편집기에 새 회차가 올라간 뒤 부른다.
  func begin(episode id: EpisodeID) {
    episodeID = id
    // 메모리에 남은 본문으로 연 경우 바로 다시 저장을 시도한다.
    if unsaved[id] != nil { scheduleSave() }
  }

  /// 회차를 떠날 때. 지금 본문을 바로 복사해 저장을 시작하되 기다리지 않는다.
  /// 저장이 끝나길 기다렸다 다음 회차를 보여주면 전환이 끊겨 보이기 때문이다.
  func leaveEpisode() {
    pendingSave?.cancel()
    pendingSave = nil
    if let job = makeSaveJob() { start(job) }
    episodeID = nil
  }

  /// 회차를 휴지통으로 보낸 뒤 부른다. 그 회차에 대해 남은 저장 정보를 버린다.
  /// (지운 회차를 나중에 저장해 파일이 되살아나는 일을 막는다. 부르기 전에 `flush`로 저장을 끝내 둔다.)
  func forget(episode id: EpisodeID) {
    if episodeID == id {
      pendingSave?.cancel()
      pendingSave = nil
      episodeID = nil
    }
    changes[id] = nil
    savedChanges[id] = nil
    unsaved[id] = nil
    inFlight[id] = nil
    if unsaved.isEmpty, case .failed = status { status = .idle }
  }

  /// 편집기에서 사용자가 글을 고칠 때마다.
  func textDidChange() {
    guard let episodeID else { return }
    changes[episodeID, default: 0] += 1
    scheduleSave()
  }

  /// 지금 저장하고, 이미 시작된 저장까지 모두 끝날 때까지 기다린다(창 비활성, 창 닫기, 종료).
  func flush() async {
    pendingSave?.cancel()
    pendingSave = nil
    if let job = makeSaveJob() { start(job) }
    while let task = running.values.first {
      await task.value
    }
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task { [delay] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      if let job = self.makeSaveJob() { self.start(job) }
    }
  }

  private func isDirty(_ id: EpisodeID) -> Bool {
    changes[id, default: 0] > savedChanges[id, default: 0] || unsaved[id] != nil
  }

  private struct SaveJob {
    let id: EpisodeID
    let change: Int
    let text: String
  }

  /// 저장할 내용을 지금 시점으로 복사한다. 키 입력마다가 아니라 저장할 때 한 번만 본문을 복사한다.
  private func makeSaveJob() -> SaveJob? {
    guard let id = episodeID, let textView, isDirty(id) else { return nil }
    return SaveJob(id: id, change: changes[id, default: 0], text: textView.string)
  }

  private func start(_ job: SaveJob) {
    let key = UUID()
    inFlight[job.id] = job.text
    running[key] = Task {
      await write(job)
      running[key] = nil
    }
  }

  private func write(_ job: SaveJob) async {
    let store = store
    status = .saving
    let indicator = Task {
      try? await Task.sleep(for: .milliseconds(500))
      if !Task.isCancelled, status == .saving { showsSavingIndicator = true }
    }
    defer {
      indicator.cancel()
      showsSavingIndicator = false
    }
    do {
      _ = try await queue.save(.episode(job.id), change: job.change) {
        try store.writeEpisode(job.text, id: job.id)
      }
      savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
      // 방금 저장한 본문에는 메모리에 남아 있던 내용도 들어 있으므로 지운다.
      if savedChanges[job.id, default: 0] >= changes[job.id, default: 0] { unsaved[job.id] = nil }
      if unsaved.isEmpty { status = .idle }
    } catch {
      unsaved[job.id] = job.text
      let message = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      status = .failed(message)
    }
    if inFlight[job.id] == job.text { inFlight[job.id] = nil }
  }
}

/// 열린 모든 자동 저장기. 앱을 끌 때 남은 저장을 마치기 위해 쓴다.
@MainActor
final class AutosaverRegistry {
  static let shared = AutosaverRegistry()
  private var items: [WeakAutosaver] = []

  private struct WeakAutosaver {
    weak var value: EpisodeAutosaver?
  }

  func register(_ autosaver: EpisodeAutosaver) {
    items.removeAll { $0.value == nil }
    items.append(WeakAutosaver(value: autosaver))
  }

  var all: [EpisodeAutosaver] { items.compactMap(\.value) }
}
