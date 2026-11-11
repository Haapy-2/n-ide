import AppKit
import NovelCore
import Observation

/// 회차 자동 저장 (SPEC 6장, 7장 4번).
/// - 입력이 멈추고 1초 뒤 저장한다. 회차 전환·창 비활성·앱 종료 때는 바로 저장한다(`flush`).
/// - 실제 쓰기는 `SaveQueue`가 순서대로 처리하고 실패하면 재시도한다.
/// - 끝내 실패하면 그 회차 본문을 메모리(`unsaved`)에 들고 있다가, 그 회차를 다시 열 때 디스크 대신 이것을 보여준다.
/// - 텍스트 저장소는 읽기만 한다. 그래서 한글 조합 중에 저장해도 조합이 끊기지 않는다.
/// - 외부 변경(8단계): 창이 다시 활성화될 때와 저장 직전에 파일이 앱 밖에서 바뀌었는지 본다.
///   앱 쪽 변경이 없으면 조용히 다시 읽고, 양쪽 다 바뀌었으면 앱 쪽을 스냅샷으로 남긴 뒤 사용자에게 묻는다(`conflicts`).
@MainActor
@Observable
final class EpisodeAutosaver {
  enum Status: Equatable {
    case idle
    case saving
    case failed(String)
  }

  /// 외부 변경과 부딪친 회차. 사용자가 고를 때까지 그 회차는 저장하지 않는다.
  struct Conflict: Equatable {
    let episodeID: EpisodeID
    /// 디스크의 지금 상태(앱 밖에서 바뀐 내용).
    let disk: DiskVersion
    /// 앱 쪽 본문을 남긴 스냅샷. 남기는 중이면 nil.
    var snapshot: URL?
    /// 스냅샷 쓰기를 마쳤는지(실패 포함). 마친 뒤에 묻는다.
    var isReady = false
  }

  private(set) var status: Status = .idle
  private(set) var conflicts: [EpisodeID: Conflict] = [:]
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
  /// 회차마다 앱이 마지막으로 읽거나 쓴 디스크 상태. 외부 변경 판단의 기준.
  @ObservationIgnored let disk = DiskVersions()

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

  /// 편집기에 새 회차가 올라간 뒤 부른다. 디스크에서 읽었으면 그때의 상태(`version`)를 함께 준다.
  /// (메모리에 남은 본문으로 열었으면 nil: 기준은 전에 기억한 것을 그대로 쓴다.)
  func begin(episode id: EpisodeID, version: DiskVersion? = nil) {
    episodeID = id
    if let version { disk[id] = version }
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
    conflicts[id] = nil
    disk[id] = nil
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

  // MARK: - 외부 변경

  /// 창이 다시 활성화될 때. 지금 회차 파일이 앱 밖에서 바뀌었는지 백그라운드에서 본다.
  func checkExternalChange() async {
    guard let id = episodeID, conflicts[id] == nil, let known = disk[id] else { return }
    let store = store
    let disk = disk
    let result = await Task.detached { () -> DiskCheck? in
      guard let result = try? store.checkEpisode(id, against: known) else { return nil }
      if case .unchanged(let refreshed) = result {
        if refreshed != known { _ = disk.replace(id, ifStill: known, with: refreshed) }
        return result
      }
      // 확인하는 사이에 앱이 저장해 기준이 바뀌었으면, 방금 본 변경은 앱 자신의 저장일 수 있어 버린다.
      // (진짜 외부 변경이었다면 그 저장이 쓰기 직전 확인에서 먼저 알아챈다.)
      return disk[id] == known ? result : nil
    }.value
    // 기다리는 사이 회차가 바뀌었거나 저장이 끝나 기준이 바뀌었으면 손대지 않는다.
    guard let result, episodeID == id, conflicts[id] == nil, disk[id] == known else { return }
    switch result {
    case .unchanged:
      break
    case .missing:
      // 앱 밖에서 본문 파일이 지워졌다. 앱이 들고 있는 본문으로 다시 써서 원고를 지킨다.
      changes[id, default: 0] += 1
      scheduleSave()
    case .changed(let diskVersion):
      if hasAppChanges(id) {
        raiseConflict(id, disk: diskVersion, appText: textView?.string ?? "")
      } else {
        // 앱 쪽 변경이 없으니 묻지 않고 바깥 내용으로 바꾼다. 결정과 교체 사이에 await가 없어 그 사이 입력이 끼어들지 못한다.
        disk[id] = diskVersion
        textView?.reloadText(with: diskVersion.text)
      }
    }
  }

  /// 앱 쪽에 아직 디스크에 없는 내용이 있는지: 저장 안 된 입력, 쓰는 중인 저장, 조합 중인 글자.
  private func hasAppChanges(_ id: EpisodeID) -> Bool {
    isDirty(id) || inFlight[id] != nil || (textView?.hasMarkedText() ?? false)
  }

  /// 양쪽 다 바뀌었다. 앱 쪽 본문을 메모리에 붙잡아 두고 스냅샷으로 남긴 뒤, 다 남기면 묻는다(`conflicts`).
  private func raiseConflict(_ id: EpisodeID, disk diskVersion: DiskVersion, appText: String) {
    guard conflicts[id] == nil else { return }
    // 지금 보고 있는 회차면 저장 작업에 복사해 둔 것보다 화면의 본문이 더 새것이다.
    let text = (id == episodeID ? textView?.string : nil) ?? appText
    unsaved[id] = text
    conflicts[id] = Conflict(episodeID: id, disk: diskVersion)
    let store = store
    Task {
      let snapshot = try? await Task.detached { try store.writeConflictSnapshot(text, episode: id) }.value
      conflicts[id]?.snapshot = snapshot
      conflicts[id]?.isReady = true
    }
  }

  /// 사용자가 "이 앱의 내용"을 골랐다. 덮어쓸 바깥 내용도 스냅샷으로 남긴 뒤 앱 쪽 본문을 저장한다.
  func keepAppVersion(_ id: EpisodeID) async {
    guard let conflict = conflicts[id], conflict.isReady else { return }
    let store = store
    // 남기지 못하는 경우는 디스크에 쓸 수 없는 경우라 아래 저장도 실패하고 앱 쪽 본문은 메모리에 남는다.
    _ = try? await Task.detached {
      try store.writeConflictSnapshot(conflict.disk.text, episode: id, label: "external")
    }.value
    guard conflicts.removeValue(forKey: id) != nil else { return }
    // 디스크의 지금 상태를 알고 덮어쓴다는 뜻으로 기준을 바꾼다. 그 뒤 또 바뀌었으면 저장 직전 확인이 다시 묻는다.
    disk[id] = conflict.disk
    changes[id, default: 0] += 1
    let text = id == episodeID ? textView?.string : unsaved[id]
    if let text {
      pendingSave?.cancel()
      pendingSave = nil
      start(SaveJob(id: id, change: changes[id, default: 0], text: text))
    }
  }

  /// 사용자가 "바깥에서 바뀐 내용"을 골랐다. 앱 쪽 본문은 이미 스냅샷에 있다.
  /// 고르는 동안 또 바뀌었을 수 있어 지금 내용을 다시 읽는다. 회차 전환처럼 바로 읽는다(5,000자 안팎, 0.1ms 수준):
  /// 기다리는 사이에 친 글자가 곧바로 덮여 사라지지 않게 하려는 것이다.
  func useDiskVersion(_ id: EpisodeID) {
    guard let conflict = conflicts.removeValue(forKey: id) else { return }
    let version = (try? store.readEpisodeVersion(id)) ?? conflict.disk
    disk[id] = version
    unsaved[id] = nil
    inFlight[id] = nil
    savedChanges[id] = changes[id, default: 0]
    if id == episodeID { textView?.reloadText(with: version.text) }
    if unsaved.isEmpty, case .failed = status { status = .idle }
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
    guard let id = episodeID, let textView, isDirty(id), conflicts[id] == nil else { return nil }
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
    let disk = disk
    do {
      // 저장 직전 확인: 쓰기 직전에 디스크를 기준과 비교하고, 앱 밖에서 바뀌었으면 쓰지 않는다.
      let result = try await queue.save(.episode(job.id), change: job.change, writeReturning: {
        let result = try store.writeEpisode(job.text, id: job.id, ifUnchangedSince: disk[job.id])
        if case .written(let version) = result { disk[job.id] = version }
        return result
      })
      if case .conflict(let diskVersion) = result {
        if inFlight[job.id] == job.text { inFlight[job.id] = nil }
        raiseConflict(job.id, disk: diskVersion, appText: job.text)
        if status == .saving { status = .idle }
        return
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
