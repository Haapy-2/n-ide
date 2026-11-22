import AppKit
import NovelCore
import Observation

/// 회차 자동 저장 (SPEC 6장, 7장 4번).
/// - 입력이 멈추고 1초 뒤 저장한다. 회차 전환·창 비활성·앱 종료 때는 바로 저장한다(`startSave`·`flush`).
/// - 실제 쓰기는 `SaveQueue`가 순서대로 처리하고 실패하면 재시도한다.
/// - 끝내 실패하면 그 회차 본문을 메모리(`unsaved`)에 들고 있다가, 그 회차를 다시 열 때 디스크 대신 이것을 보여준다.
/// - 텍스트 저장소는 읽기만 한다. 그래서 한글 조합 중에 저장해도 조합이 끊기지 않는다.
/// - 외부 변경: 창이 다시 활성화될 때와 저장 직전에 파일이 앱 밖에서 바뀌었는지 본다.
///   앱 쪽 변경이 없으면 조용히 다시 읽고, 양쪽 다 바뀌었으면 앱 쪽을 스냅샷으로 남긴 뒤 사용자에게 묻는다(`conflicts`).
/// - 버전 스냅샷은 `snapshots`가 찍는다. 떠날 때는 저장하려고 복사한 본문을 그대로 넘겨 한 번 더 복사하지 않는다.
@MainActor
@Observable
final class EpisodeAutosaver {
  enum Status: Equatable {
    case idle
    case saving
    /// 저장이 실패해 다시 시도하는 중.
    case retrying
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
  /// 되돌린 직후 상태 줄에 띄우는 알림(`14:23:05 버전으로 되돌렸어요`). 다음 입력이나 회차 전환에 사라진다.
  private(set) var restoreNotice: String?

  let store: ProjectStore
  let snapshots: EpisodeSnapshotter
  private let queue: SaveQueue
  private let delay: Duration
  private let maxWait: Duration
  @ObservationIgnored private weak var textView: ManuscriptTextView?
  @ObservationIgnored private(set) var episodeID: EpisodeID?
  /// 회차별 변경 번호. 입력할 때마다 1씩 오른다.
  @ObservationIgnored private var changes: [EpisodeID: Int] = [:]
  @ObservationIgnored private var savedChanges: [EpisodeID: Int] = [:]
  /// 저장에 실패한 회차의 본문. 변경 번호를 함께 들어, 쓰는 중인 본문과 어느 쪽이 더 새것인지 가린다.
  @ObservationIgnored private var unsaved: [EpisodeID: SaveJob] = [:]
  /// 파일에 쓰는 중인 회차의 본문.
  @ObservationIgnored private var inFlight: [EpisodeID: SaveJob] = [:]
  @ObservationIgnored private var running: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  /// 지금 회차에서 아직 저장을 시작하지 않은 첫 변경의 시각.
  @ObservationIgnored private var waitingSince: ContinuousClock.Instant?
  /// 마지막 저장 실패의 설명. 실패한 원고가 남아 있는 동안 상태 줄에 보인다.
  @ObservationIgnored private var lastFailure = ""
  @ObservationIgnored let disk = DiskVersions()

  init(
    store: ProjectStore, queue: SaveQueue = SaveQueue(), delay: Duration = .seconds(1), maxWait: Duration = .seconds(10)
  ) {
    self.store = store
    self.queue = queue
    self.delay = delay
    self.maxWait = maxWait
    snapshots = EpisodeSnapshotter(store: store)
    AutosaverRegistry.shared.register(self)
    snapshots.currentEpisode = { [weak self] in self?.episodeID }
    snapshots.currentText = { [weak self] in self?.textView?.string }
  }

  /// 앱을 끄기 전에 마칠 일이 있는지: 저장 안 된 변경, 아직 안 찍은 떠날 때 스냅샷, 쓰는 중인 스냅샷.
  var hasWorkBeforeQuit: Bool { hasUnsavedChanges || snapshots.hasPendingWork || hasProjectWork() }

  /// 작품 쪽(`project.json`: 회차 목록, 미뤄 둔 글자 수)에 끝낼 저장이 있는지와 그것을 끝내는 일. `ProjectModel`이 건다.
  /// 앱 종료는 자동 저장기 목록만 보므로 여기에 걸어 함께 기다리게 한다.
  @ObservationIgnored var hasProjectWork: () -> Bool = { false }
  @ObservationIgnored var finishProjectWork: () async -> Void = {}

  /// 저장 안 된 변경이 있는지 (지금 회차 또는 저장에 실패한 회차).
  var hasUnsavedChanges: Bool {
    if let episodeID, isDirty(episodeID) { return true }
    return !unsaved.isEmpty || !running.isEmpty
  }

  /// 회차 제목. 저장하지 못한 원고를 다른 곳으로 내보낼 때 파일 이름으로 쓴다. `ProjectModel`이 건다.
  @ObservationIgnored var episodeTitle: (EpisodeID) -> String = { _ in "" }
  @ObservationIgnored var projectTitle: () -> String = { "" }

  /// 저장에 끝내 실패한 원고를 작품 밖에 따로 두는 곳. 없으면(테스트 기본값) 백업하지 않는다.
  @ObservationIgnored var backup: EmergencyBackup?
  /// 이번 실행에서 백업한 회차와 그 변경 번호. 그보다 새 본문이 저장되면 백업을 지운다.
  @ObservationIgnored private var backedUp: [EpisodeID: Int] = [:]
  /// 백업 쓰기·지우기를 차례대로(옛 쓰기가 새 지우기 뒤에 끝나 낡은 백업이 남지 않게).
  @ObservationIgnored private var backupTail: Task<Void, Never>?

  /// 끝내 저장하지 못해 메모리에만 있는 원고(창 닫기·앱 종료 때 다른 곳으로 내보내려고).
  func unsavedManuscripts() -> [(title: String, text: String)] {
    unsaved.values.sorted { $0.id.rawValue < $1.id.rawValue }.map { (episodeTitle($0.id), $0.text) }
  }

  /// 사용자가 다른 곳으로 내보냈다. 메모리의 원고를 놓아 더는 "저장 안 됨"으로 세지 않는다.
  func markRescued() {
    for id in unsaved.keys { savedChanges[id] = max(savedChanges[id, default: 0], changes[id, default: 0]) }
    unsaved.removeAll()
    if case .failed = status { settleStatus() }
  }

  func attach(_ textView: ManuscriptTextView) {
    self.textView = textView
  }

  /// 회차를 열 때 디스크 대신 보여줄 본문: 저장에 실패해 메모리에 남은 것, 또는 아직 쓰는 중인 것. 없으면 nil.
  /// (빠르게 A→B→A로 돌아왔을 때 A 저장이 끝나기 전 디스크의 옛 본문을 읽지 않기 위해서다.)
  /// 둘 다 있으면(실패한 뒤 더 쓰고 떠나 새 저장이 아직 쓰는 중) 변경 번호가 큰 쪽이 더 새 본문이다.
  /// 옛 실패 본문을 보여 주면 이어 쓴 글이 그사이 쓴 글을 덮는다.
  func pendingText(for id: EpisodeID) -> String? {
    guard let failed = unsaved[id] else { return inFlight[id]?.text }
    guard let writing = inFlight[id], writing.change > failed.change else { return failed.text }
    return writing.text
  }

  /// 작품 전체 검색이 파일 대신 찾을 글: 저장하지 못했거나 아직 쓰는 중인 글, 그리고 열린 회차는 편집기의 지금 글.
  /// 디스크 파일은 1초 전 글일 수 있어서, 방금 친 글도 찾히게 한다.
  func searchTexts() -> [EpisodeID: String] {
    var texts: [EpisodeID: String] = [:]
    for id in Set(unsaved.keys).union(inFlight.keys) { texts[id] = pendingText(for: id) }
    if let episodeID, let textView { texts[episodeID] = textView.string }
    return texts
  }

  /// 편집기에 새 회차가 올라간 뒤 부른다. 디스크에서 읽었으면 그때의 상태(`version`)를 함께 준다.
  /// (메모리에 남은 본문으로 열었으면 nil: 기준은 전에 기억한 것을 그대로 쓴다.)
  func begin(episode id: EpisodeID, version: DiskVersion? = nil) {
    episodeID = id
    waitingSince = nil
    if let version { disk[id] = version }
    // 메모리에 남은 본문으로 연 경우 바로 다시 저장을 시도한다.
    if unsaved[id] != nil { scheduleSave() }
  }

  /// 회차를 떠날 때. 지금 본문을 바로 복사해 저장을 시작하되 기다리지 않는다.
  /// 저장이 끝나길 기다렸다 다음 회차를 보여주면 전환이 끊겨 보이기 때문이다.
  func leaveEpisode() {
    restoreNotice = nil
    snapshotLeaving()
    let left = episodeID
    episodeID = nil
    if let left { releaseBaselineIfIdle(left) }
  }

  /// 떠난 회차의 디스크 기준을 놓는다. 기준은 본문 전체를 들고 있어서, 그대로 두면 훑어본 회차만큼 메모리에 쌓인다.
  /// 저장할 것도 쓰는 중인 것도 없을 때만 놓는다. 다시 열면 디스크에서 새로 읽어 기준을 잡는다.
  private func releaseBaselineIfIdle(_ id: EpisodeID) {
    guard id != episodeID, !isDirty(id), inFlight[id] == nil, conflicts[id] == nil else { return }
    disk[id] = nil
  }

  /// 디스크 기준을 들고 있는 회차인지(테스트용).
  func holdsBaseline(for id: EpisodeID) -> Bool { disk[id] != nil }

  /// 창을 닫을 때 그 자리에서 부른다: `finish`의 앞부분(떠날 때 스냅샷·저장 시작)만 기다리지 않고 한다.
  /// 창 닫기 처리가 끝나면 편집기(약한 참조)가 먼저 사라질 수 있어서, 본문은 그 전에 복사해 둔다.
  func startFinishing() {
    snapshotLeaving()
  }

  /// 창을 닫거나 앱을 끌 때: 떠날 때 스냅샷을 남기고, 저장과 스냅샷 쓰기가 다 끝날 때까지 기다린다.
  func finish() async {
    snapshotLeaving()
    await flush()
    await backupTail?.value
    await snapshots.waitForWrites()
    await finishProjectWork()
  }

  /// 저장을 시작하고, 이번에 고친 회차면 같은 본문으로 `leave` 스냅샷을 남긴다.
  private func snapshotLeaving() {
    pendingSave?.cancel()
    pendingSave = nil
    let job = makeSaveJob()
    if let job { start(job) }
    if let id = episodeID { snapshots.leave(id) { job?.text ?? textView?.string } }
  }

  /// 직접 찍기(⌃⌘S): 저장을 먼저 끝낸 뒤 지금 본문을 찍는다. 열린 회차가 없으면 nil.
  /// `skipIfUnchanged`면 마지막 스냅샷과 같을 때도 nil(저장하면서 스냅샷 찍기).
  func takeManualSnapshot(skipIfUnchanged: Bool = false) async throws -> Snapshot? {
    guard let id = episodeID else { return nil }
    await flush()
    guard id == episodeID, let text = textView?.string else { return nil }
    return try await snapshots.takeManual(id, text: text, skipIfUnchanged: skipIfUnchanged)
  }

  /// 떠 있는 판(⇧⌘S)을 열 때: 편집기의 조합을 끝내고 초점을 내려놓은 뒤 지금 본문을 한 번 복사해 준다.
  /// 편집기가 없으면 nil. `hadFocus`는 닫을 때 `endPanel`에 그대로 돌려준다.
  func beginPanel() -> (text: String, hadFocus: Bool)? {
    guard let textView else { return nil }
    let hadFocus = textView.yieldFocusForPanel()
    return (textView.string, hadFocus)
  }

  func endPanel(hadFocus: Bool) {
    if hadFocus { textView?.regainFocusAfterPanel() }
  }

  /// 회차를 휴지통으로 보낸 뒤 부른다. 그 회차에 대해 남은 저장 정보를 버린다.
  /// (지운 회차를 나중에 저장해 파일이 되살아나는 일을 막는다. 부르기 전에 `flush`로 저장을 끝내 둔다.)
  func forget(episode id: EpisodeID) {
    if episodeID == id {
      pendingSave?.cancel()
      pendingSave = nil
      episodeID = nil
    }
    // 변경 번호는 0으로 되돌리지 않는다. 저장 줄(SaveQueue)이 이 회차에 쓴 마지막 번호를 기억하고 있어서,
    // ⌘Z로 휴지통에서 꺼낸 뒤 1부터 다시 세면 새 저장이 "옛 저장"으로 보여 조용히 건너뛰어진다.
    if let change = changes[id] { savedChanges[id] = change }
    unsaved[id] = nil
    inFlight[id] = nil
    conflicts[id] = nil
    disk[id] = nil
    removeBackup(id)
    snapshots.forget(id)
    if case .failed = status { settleStatus() }
  }

  func textDidChange() {
    restoreNotice = nil
    guard let episodeID else { return }
    noteChange(episodeID)
  }

  private func noteChange(_ id: EpisodeID) {
    changes[id, default: 0] += 1
    snapshots.noteEdit(id)
    scheduleSave()
  }

  // MARK: - 스냅샷으로 되돌리기 (PLAN 10장 6번)

  enum RestoreError: Error {
    case notOpen
    /// 외부 변경 충돌을 아직 고르지 않았다.
    case conflict
    /// 복원 전 스냅샷을 남기는 사이 회차나 본문이 바뀌었다.
    case changedMeanwhile
  }

  /// 지금 본문을 `restore` 스냅샷(메모 포함)으로 먼저 남기고, 남긴 뒤에만 편집기 본문을 바꾼다.
  /// 남기지 못하면 오류를 던지고 본문은 그대로다. 바꾼 뒤의 저장은 평소 자동 저장에 맡긴다(본문 파일을 직접 덮지 않음).
  /// 지금과 같아서 바꿀 것이 없으면 false.
  func restore(_ id: EpisodeID, to text: String, memo: String, notice: String) async throws -> Bool {
    guard id == episodeID, let textView else { throw RestoreError.notOpen }
    guard conflicts[id] == nil else { throw RestoreError.conflict }
    let current = textView.string
    guard current != text else { return false }
    _ = try await snapshots.takeRestore(id, text: current, memo: memo)
    // 기다리는 사이 바뀌었으면 손대지 않는다. 남긴 스냅샷은 그대로 둔다(지워서 좋을 것이 없다).
    guard id == episodeID, conflicts[id] == nil, self.textView === textView, !textView.hasMarkedText(),
      textView.string == current
    else { throw RestoreError.changedMeanwhile }
    guard textView.replaceAllUndoably(with: text, actionName: "스냅샷으로 되돌리기") else { return false }
    // 편집기 알림으로도 들어오지만(두 번 세어도 해롭지 않다), 알림이 없는 경우에도 저장되게 직접 센다.
    noteChange(id)
    restoreNotice = notice
    return true
  }

  /// 상태 줄의 "취소": 되돌리기 직전으로. 알림이 떠 있으면 그 뒤로 고친 것이 없으므로 실행 취소 맨 위가 되돌리기다.
  func undoRestore() {
    guard restoreNotice != nil, let textView, let id = episodeID else { return }
    restoreNotice = nil
    textView.undo(nil)
    noteChange(id)
    textView.regainFocusAfterPanel()
  }

  /// 지금 본문을 그 자리에서 복사해 저장을 시작만 한다(창 비활성). 끝나기는 기다리지 않는다.
  /// `Task` 안에서 부르면 창 닫기 처리가 끝난 뒤에야 돌아, 그사이 편집기(약한 참조)가 사라지면 본문을 못 읽는다.
  func startSave() {
    pendingSave?.cancel()
    pendingSave = nil
    if let job = makeSaveJob() { start(job) }
  }

  /// 지금 저장하고, 이미 시작된 저장까지 모두 끝날 때까지 기다린다(⌘S, 창 닫기, 종료).
  /// 저장에 실패해 메모리에 남은 다른 회차도 다시 저장한다. 열린 회차만 저장하면 창을 닫을 때 그 원고가 사라진다.
  func flush() async {
    startSave()
    for job in unsaved.values where job.id != episodeID && inFlight[job.id] == nil && conflicts[job.id] == nil {
      start(job)
    }
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
    unsaved[id] = SaveJob(id: id, change: changes[id, default: 0], text: text)
    conflicts[id] = Conflict(episodeID: id, disk: diskVersion)
    let store = store
    Task {
      let snapshot = try? await Task.detached { try store.writeSnapshot(text, episode: id, kind: .conflict)?.url }.value
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
      try store.writeSnapshot(conflict.disk.text, episode: id, kind: .external)
    }.value
    guard conflicts.removeValue(forKey: id) != nil else { return }
    // 디스크의 지금 상태를 알고 덮어쓴다는 뜻으로 기준을 바꾼다. 그 뒤 또 바뀌었으면 저장 직전 확인이 다시 묻는다.
    disk[id] = conflict.disk
    changes[id, default: 0] += 1
    let text = id == episodeID ? textView?.string : unsaved[id]?.text
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
    removeBackup(id)
    savedChanges[id] = changes[id, default: 0]
    if id == episodeID { textView?.reloadText(with: version.text) }
    if case .failed = status { settleStatus() }
  }

  /// 저장 하나가 끝나면 상태 줄을 실제 상태에 맞춘다. 마지막 저장의 결과로 덮으면, 다른 회차가 저장된 뒤
  /// 앞 회차의 실패 표시가 사라지고 "저장 중"에 멈춘다. 충돌은 실패로 보이지 않는다.
  private func settleStatus() {
    status = unsaved.keys.contains { conflicts[$0] == nil } ? .failed(lastFailure) : .idle
  }

  /// 입력이 `delay`만큼 멈추면 저장한다. 쉬지 않고 계속 치면 이 기다림이 끝없이 미뤄지므로,
  /// 저장하지 않은 첫 변경부터 `maxWait`이 지나면 멈춤을 기다리지 않는다.
  private func scheduleSave() {
    pendingSave?.cancel()
    let now = ContinuousClock.now
    let since = waitingSince ?? now
    waitingSince = since
    let wait = min(delay, max(.zero, since + maxWait - now))
    pendingSave = Task { [wait] in
      if wait > .zero { try? await Task.sleep(for: wait) }
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
    if job.id == episodeID { waitingSince = nil }
    let key = UUID()
    inFlight[job.id] = job
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
      }, didWrite: { if case .written = $0 { true } else { false } }, onRetry: { [weak self] in
        Task { @MainActor in
          if self?.status == .saving { self?.status = .retrying }
        }
      })
      if case .conflict(let diskVersion) = result {
        if inFlight[job.id]?.text == job.text { inFlight[job.id] = nil }
        raiseConflict(job.id, disk: diskVersion, appText: job.text)
        settleStatus()
        return
      }
      savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
      // 메모리에 남아 있던 본문이 방금 저장한 것보다 옛것이면 그 내용은 이미 디스크에 있으므로 지운다.
      // (그 뒤에 더 친 글이 있어도 지운다. 그 글은 편집기에 있고 다음 저장이 맡는다.)
      if let failed = unsaved[job.id], failed.change <= job.change { unsaved[job.id] = nil }
      if let backed = backedUp[job.id], backed <= job.change { removeBackup(job.id) }
      settleStatus()
    } catch {
      // 더 새 본문이 이미 저장됐거나 메모리에 남아 있으면 이 실패는 지난 일이다. 옛 본문으로 덮지 않는다.
      if savedChanges[job.id, default: 0] < job.change, (unsaved[job.id]?.change ?? 0) <= job.change {
        unsaved[job.id] = job
        backUp(job)
        lastFailure = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      }
      settleStatus()
    }
    if inFlight[job.id]?.text == job.text { inFlight[job.id] = nil }
    releaseBaselineIfIdle(job.id)
  }

  // MARK: - 비상 백업 (PLAN 17장 1번)

  private func backUp(_ job: SaveJob) {
    guard let backup else { return }
    backedUp[job.id] = job.change
    let episodeTitle = episodeTitle(job.id)
    let projectTitle = projectTitle()
    let text = job.text
    let id = job.id
    enqueueBackup { try backup.write(text, episode: id, episodeTitle: episodeTitle, projectTitle: projectTitle) }
  }

  private func removeBackup(_ id: EpisodeID) {
    guard let backup, backedUp.removeValue(forKey: id) != nil else { return }
    enqueueBackup { try backup.remove(id) }
  }

  /// 백업을 못 써도 원고는 메모리에 남고 상태 줄이 실패를 보여 주므로, 오류는 삼킨다.
  private func enqueueBackup(_ work: @escaping @Sendable () throws -> Void) {
    let previous = backupTail
    backupTail = Task.detached(priority: .utility) {
      await previous?.value
      try? work()
    }
  }

  /// 테스트: 쌓인 백업 작업이 끝날 때까지.
  func waitForBackups() async {
    await backupTail?.value
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

  /// 창은 닫혔지만 저장하지 못한 원고를 든 저장기. 앱을 끌 때 다시 묻도록 놓지 않는다.
  private var orphans: [EpisodeAutosaver] = []

  func register(_ autosaver: EpisodeAutosaver) {
    items.removeAll { $0.value == nil }
    items.append(WeakAutosaver(value: autosaver))
  }

  func keepAlive(_ autosaver: EpisodeAutosaver) {
    if !orphans.contains(where: { $0 === autosaver }) { orphans.append(autosaver) }
  }

  func release(_ autosaver: EpisodeAutosaver) {
    orphans.removeAll { $0 === autosaver }
  }

  var all: [EpisodeAutosaver] { items.compactMap(\.value) }
}
