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
    return !unsaved.isEmpty
  }

  func attach(_ textView: ManuscriptTextView) {
    self.textView = textView
  }

  /// 회차를 열 때 디스크 대신 보여줄 본문(저장에 실패해 메모리에 남은 것). 없으면 nil.
  func unsavedText(for id: EpisodeID) -> String? {
    unsaved[id]
  }

  /// 편집기에 새 회차가 올라간 뒤 부른다.
  func begin(episode id: EpisodeID) {
    episodeID = id
    // 메모리에 남은 본문으로 연 경우 바로 다시 저장을 시도한다.
    if unsaved[id] != nil { scheduleSave() }
  }

  /// 편집기에서 사용자가 글을 고칠 때마다.
  func textDidChange() {
    guard let episodeID else { return }
    changes[episodeID, default: 0] += 1
    scheduleSave()
  }

  /// 기다리지 않고 지금 저장한다(회차 전환, 창 비활성, 종료).
  func flush() async {
    pendingSave?.cancel()
    pendingSave = nil
    await save()
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task { [delay] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self.save()
    }
  }

  private func isDirty(_ id: EpisodeID) -> Bool {
    changes[id, default: 0] > savedChanges[id, default: 0] || unsaved[id] != nil
  }

  private func save() async {
    guard let id = episodeID, let textView, isDirty(id) else { return }
    let change = changes[id, default: 0]
    // 저장할 때 한 번만 본문을 복사한다(키 입력마다 복사하지 않음).
    let text = textView.string
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
      _ = try await queue.save(.episode(id), change: change) {
        try store.writeEpisode(text, id: id)
      }
      savedChanges[id] = max(savedChanges[id, default: 0], change)
      // 방금 저장한 본문에는 메모리에 남아 있던 내용도 들어 있으므로 지운다.
      unsaved[id] = nil
      if unsaved.isEmpty { status = .idle }
    } catch {
      unsaved[id] = text
      let message = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      status = .failed(message)
    }
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
