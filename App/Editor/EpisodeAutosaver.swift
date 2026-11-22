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
    case failed(Failure)
  }

  /// 저장 실패 표시. `label`은 상태 줄 한 줄, `detail`은 눌렀을 때 보이는 설명.
  struct Failure: Equatable {
    var label = WriteProblem.other.statusLabel
    var detail = ""
    var isBackedUp = false

    init() {}

    init(_ error: Error, isBackedUp: Bool) {
      let problem: WriteProblem =
        if case ProjectError.writeFailed(_, _, let problem) = error { problem } else { WriteProblem(error: error) }
      label = problem.statusLabel
      detail = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      self.isBackedUp = isBackedUp
    }
  }

  /// 외부 변경과 부딪친 회차. 사용자가 고를 때까지 그 회차는 저장하지 않는다.
  struct Conflict: Equatable {
    let episodeID: EpisodeID
    /// 디스크의 지금 상태(앱 밖에서 바뀐 내용).
    let disk: DiskVersion
    /// 충돌이 났을 때의 변경 번호. 그 뒤에 더 고쳤으면 스냅샷에 없는 글이 있다.
    let change: Int
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
  @ObservationIgnored private var lastFailure = Failure()
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
  var hasWorkBeforeQuit: Bool {
    hasUnsavedChanges || snapshots.hasPendingWork || hasProjectWork() || bulkRewrites > 0
  }

  /// 진행 중인 여러 회차 고쳐 쓰기(전체 바꾸기·되돌리기·다시 바꾸기). 회차와 회차 사이에는 쓰는 중인 저장이 없어
  /// 그 순간 종료·창 닫기가 일부 회차만 바뀐 채 끝나지 않게, 끝날 때까지 기다린다.
  @ObservationIgnored private var bulkRewrites = 0
  /// 편집기에서 마지막으로 글이 바뀐 때. 열린 회차를 고쳐 쓰기 전에 입력이 멈추기를 기다리는 데 쓴다.
  @ObservationIgnored private var lastInput: ContinuousClock.Instant?
  /// 두벌식 입력기(macOS 27)가 표시된 글자 없이 조합을 이어 갈 때는 `hasMarkedText`가 false라 조합 중인지 알 수 없다.
  /// 그 틈에 고치면 입력기가 잇던 글자를 놓게 되어(`forgetInputInProgress`) 글자가 쪼개지므로(가 + ㄱ → "가ㄱ"),
  /// 입력이 이만큼 멈춘 뒤에 고친다.
  static let inputPause: Duration = .milliseconds(500)

  func beginBulkRewrite() { bulkRewrites += 1 }
  func endBulkRewrite() { bulkRewrites -= 1 }

  /// 작품 쪽(`project.json`: 회차 목록, 미뤄 둔 글자 수)에 끝낼 저장이 있는지와 그것을 끝내는 일. `ProjectModel`이 건다.
  /// 앱 종료는 자동 저장기 목록만 보므로 여기에 걸어 함께 기다리게 한다.
  @ObservationIgnored var hasProjectWork: () -> Bool = { false }
  @ObservationIgnored var finishProjectWork: () async -> Void = {}

  /// 저장 안 된 변경이 있는지 (지금 회차 또는 저장에 실패한 회차, 외부 변경 충돌을 고르지 않은 회차).
  var hasUnsavedChanges: Bool {
    if let episodeID, isDirty(episodeID) { return true }
    return !unsaved.isEmpty || !running.isEmpty
  }

  /// 저장 안 된 변경 중 어디에도 남지 않은 것이 있는지. 다시 시도·내보내기는 이것만 다룬다.
  /// 충돌 회차의 앱 쪽 글은 `conflict` 스냅샷에 그대로 있으면 지켜진 것으로 본다(저장을 다시 해도 충돌은 풀리지 않는다).
  var hasUnprotectedChanges: Bool {
    if let episodeID, isDirty(episodeID), !isKeptInSnapshot(episodeID) { return true }
    return unsaved.keys.contains { !isKeptInSnapshot($0) } || !running.isEmpty
  }

  /// 고르지 않은 충돌 중 앱 쪽 글이 스냅샷에 그대로 남은 회차 수. 종료 때 따로 알린다.
  var conflictsKeptInSnapshots: Int { conflicts.keys.filter(isKeptInSnapshot).count }

  /// 지켜지지 않은 원고가 모두 작품 밖 백업에 있는지(종료 경고 문구). 충돌 회차는 백업하지 않는다.
  var unprotectedAreBackedUp: Bool {
    backup != nil && !unsaved.keys.contains { conflicts[$0] != nil && !isKeptInSnapshot($0) }
  }

  private func isKeptInSnapshot(_ id: EpisodeID) -> Bool {
    guard let conflict = conflicts[id], conflict.snapshot != nil else { return false }
    return changes[id, default: 0] == conflict.change
  }

  /// 회차 제목. 저장하지 못한 원고를 다른 곳으로 내보낼 때 파일 이름으로 쓴다. `ProjectModel`이 건다.
  @ObservationIgnored var episodeTitle: (EpisodeID) -> String = { _ in "" }
  /// 회차가 지금 목록에 있는지. 휴지통으로 간 회차에 늦게 쓰면 지운 본문 파일이 되살아나므로 전체 바꾸기가 쓰기 직전에 본다.
  @ObservationIgnored var isListed: (EpisodeID) -> Bool = { _ in true }
  @ObservationIgnored var projectTitle: () -> String = { "" }

  /// 저장에 끝내 실패한 원고를 작품 밖에 따로 두는 곳. 없으면(테스트 기본값) 백업하지 않는다.
  @ObservationIgnored var backup: EmergencyBackup?
  /// 이번 실행에서 백업한 회차와 그 변경 번호. 그보다 새 본문이 저장되면 백업을 지운다.
  @ObservationIgnored private var backedUp: [EpisodeID: Int] = [:]
  /// 백업 쓰기·지우기를 차례대로(옛 쓰기가 새 지우기 뒤에 끝나 낡은 백업이 남지 않게).
  @ObservationIgnored private var backupTail: Task<Void, Never>?

  /// 끝내 저장하지 못해 메모리에만 있는 원고(창 닫기·앱 종료 때 다른 곳으로 내보내려고).
  /// 충돌 스냅샷에 그대로 남은 회차는 뺀다(내보낼 필요가 없다).
  func unsavedManuscripts() -> [(title: String, text: String)] {
    unsaved.values.filter { !isKeptInSnapshot($0.id) }.sorted { $0.id.rawValue < $1.id.rawValue }
      .map { (episodeTitle($0.id), $0.text) }
  }

  /// 아직 디스크에 썼다고 확인되지 않은 원고: 저장에 실패했거나, 쓰는 중이거나, 열린 회차에서 저장 전인 글.
  /// 종료가 늦어 사용자가 기다리지 않고 내보낼 때 쓴다.
  func pendingManuscripts() -> [(title: String, text: String)] {
    var texts: [EpisodeID: String] = [:]
    for id in Set(unsaved.keys).union(inFlight.keys) { texts[id] = pendingText(for: id) }
    if let episodeID, isDirty(episodeID), let textView { texts[episodeID] = textView.string }
    return texts.sorted { $0.key.rawValue < $1.key.rawValue }.map { (episodeTitle($0.key), $0.value) }
  }

  /// 사용자가 다른 곳으로 내보냈다. 메모리의 원고를 놓아 더는 "저장 안 됨"으로 세지 않는다.
  /// 충돌 스냅샷에 남은 회차는 내보내지 않았으므로 그대로 둔다(나중에 충돌을 고를 때 앱 쪽 글이 필요하다).
  func markRescued() {
    for id in unsaved.keys where !isKeptInSnapshot(id) {
      savedChanges[id] = max(savedChanges[id, default: 0], changes[id, default: 0])
      unsaved[id] = nil
    }
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
    while bulkRewrites > 0 { try? await Task.sleep(for: .milliseconds(20)) }
    snapshotLeaving()
    await flush()
    await backupTail?.value
    await snapshots.waitForWrites()
    // 바로 위 저장이 외부 변경 충돌을 막 냈으면 앱 쪽 글을 스냅샷에 다 남기기를 기다린다.
    // 남았는지에 따라 종료 경고(지켜진 충돌 / 내보낼 원고)가 갈린다.
    while conflicts.values.contains(where: { !$0.isReady }) { try? await Task.sleep(for: .milliseconds(20)) }
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
    lastInput = .now
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

  // MARK: - 전체 바꾸기·되돌리기·다시 바꾸기 (PLAN 14장 2·5번)

  /// 회차 하나를 고쳐 쓰는 일. 전체 바꾸기, 바꾼 자리만 되돌리기, 다시 바꾸기가 모두 같은 길을 간다:
  /// 지금 글을 스냅샷으로 남긴 뒤에만 고치고, 열린 회차는 조합이 끝난 뒤 편집기에서 고칠 자리만,
  /// 나머지는 저장 줄로 조건부로 쓰고 엇갈리면 다시 읽어 3번까지.
  struct Rewrite: Sendable {
    /// 지금 글에서 고칠 자리와 고치지 않고 둔 곳 수(되돌리기에서 그 뒤에 고친 곳). 메인 스레드 밖에서 부른다.
    /// 던지면(스냅샷을 읽지 못함 등) 그 회차는 읽지 못한 것으로 센다.
    let changes: @Sendable (String) throws -> (changes: [TextChange], kept: Int)
    let beforeKind: SnapshotKind
    /// 고치기 전 스냅샷 메모. 고칠 곳 수와 둔 곳 수를 받는다.
    let beforeMemo: @Sendable (_ count: Int, _ kept: Int) -> String
    /// 고친 뒤 스냅샷 메모. nil이면 남기지 않는다(전체 바꾸기만 `바꾼 뒤`를 남긴다).
    let afterMemo: (@Sendable (_ count: Int) -> String)?
    /// 스냅샷 시각. 한 번의 작업에서 모든 회차가 같은 시각을 가져 하나로 알아볼 수 있다.
    let date: Date
    /// 편집기 실행 취소 이름
    let actionName: String

    /// 전체 바꾸기. `memo` 뒤에 `· 바꾸기 전 · 12곳`이 붙는다.
    static func replace(query: String, replacement: String, caseSensitive: Bool, date: Date, memo: String) -> Self {
      Self(
        changes: { text in
          (TextReplace.ranges(of: query, in: text, caseSensitive: caseSensitive).map {
            TextChange(range: $0, text: replacement)
          }, 0)
        },
        beforeKind: .replace, beforeMemo: { count, _ in "\(memo) · 바꾸기 전 · \(count)곳" },
        afterMemo: { "\(memo) · 바꾼 뒤 · \($0)곳" }, date: date, actionName: ProjectReplace.actionName)
    }
  }

  enum RewriteOutcome: Equatable {
    /// 고쳤다. 열리지 않은 회차를 끝내 쓰지 못했으면 평소 저장 실패처럼 메모리에 붙잡고 상태 줄이 알린다.
    /// `characters`는 고친 글의 글자 수. 열린 회차는 편집기의 글자 수 세기가 맡아 nil.
    /// `바꾼 뒤` 스냅샷은 쓰기를 시작만 해 두므로 여기에 없다(같은 시각·종류 `replaced`로 찾는다).
    case done(count: Int, kept: Int, characters: CharacterCount?, before: Snapshot?)
    /// 지금 글에는 고칠 곳이 없다.
    case nothing
    /// 외부 변경 충돌을 아직 고르지 않았다.
    case conflict
    /// 고치기 전 스냅샷을 남기지 못했다.
    case snapshotFailed
    /// 본문(또는 되돌리기에 쓸 스냅샷)을 읽지 못했다.
    case unreadable
    /// 읽고 쓰는 사이에 앱 밖에서 거듭 바뀌었다.
    case keptChanging
  }

  /// 이 실행 취소 기록이 열린 회차 편집기의 것인가(편집기 ⌘Z로 전체 바꾸기를 되돌렸는지 알아볼 때).
  func ownsEditorUndo(_ manager: UndoManager) -> Bool {
    textView?.undoManager === manager
  }

  /// 회차 하나를 고친다. 센 때의 글이 아니라 고치는 순간의 지금 글에서 고칠 자리를 다시 정한다(그사이 고쳤어도 건너뛰지 않는다).
  func rewrite(_ id: EpisodeID, _ job: Rewrite) async -> RewriteOutcome {
    var before: (text: String, snapshot: Snapshot?)?
    for _ in 0..<3 {
      if let outcome = await rewriteAttempt(id, job, before: &before) { return outcome }
    }
    return .keptChanging
  }

  /// 한 번 해 본다. 그사이 상태가 바뀌어 다시 해야 하면 nil.
  private func rewriteAttempt(
    _ id: EpisodeID, _ job: Rewrite, before: inout (text: String, snapshot: Snapshot?)?
  ) async -> RewriteOutcome? {
    if id == episodeID, textView != nil { return await rewriteOpen(id, job, before: &before) }
    // 쓰는 중인 저장이 있으면 끝나기를 기다린다. 그 저장이 끝난 뒤의 글에서 고쳐야 순서가 맞는다.
    while id != episodeID, inFlight[id] != nil, let task = running.values.first {
      await task.value
    }
    if id == episodeID { return nil }
    if conflicts[id] != nil { return .conflict }
    let pending = pendingText(for: id)
    let store = store
    let source: (text: String, version: DiskVersion?)
    if let pending {
      source = (pending, nil)
    } else {
      guard let read = try? await Task.detached(operation: { try store.readEpisodeVersion(id) }).value else {
        return .unreadable
      }
      source = (read.text, read)
    }
    let (changes, text) = (job.changes, source.text)
    let computed: (text: String, count: Int, kept: Int, characters: CharacterCount)?
    do {
      computed = try await Task.detached {
        let found = try changes(text)
        guard !found.changes.isEmpty else { return nil }
        let result = TextChange.applying(found.changes, to: text)
        return (result, found.changes.count, found.kept, CharacterCount(counting: result))
      }.value
    } catch {
      return .unreadable
    }
    guard let computed else { return .nothing }
    let beforeSnapshot: Snapshot?
    do {
      beforeSnapshot = try await snapshotBefore(id, source.text, count: computed.count, kept: computed.kept, job, &before)
    } catch {
      return .snapshotFailed
    }
    // 기다리는 사이 열렸거나, 충돌이 생겼거나, 메모리의 글이 바뀌었으면 처음부터 다시.
    guard id != episodeID, conflicts[id] == nil, inFlight[id] == nil, pendingText(for: id) == pending else { return nil }
    // 스냅샷을 쓰는 사이 휴지통으로 갔으면 쓰지 않는다. 쓰기는 여기서 바로 시작되어(`running`), 그 뒤의 휴지통 보내기는
    // 저장을 기다렸다가 고친 본문째 옮긴다.
    guard isListed(id) else { return .nothing }
    guard await writeReplacement(id, text: computed.text, readVersion: source.version) else { return nil }
    if let afterMemo = job.afterMemo {
      snapshots.startReplace(id, kind: .replaced, text: computed.text, memo: afterMemo(computed.count), at: job.date)
    }
    return .done(count: computed.count, kept: computed.kept, characters: computed.characters, before: beforeSnapshot)
  }

  /// 열린 회차: 지금 글을 남긴 뒤, 한글 조합이 끝난 그 순간 지금 글에서 고칠 자리만 고친다.
  /// 고칠 자리는 메인 스레드 밖에서 정하고, 고치기 직전에 편집기 글이 그 글 그대로인지 본다(사이에 await가 없어
  /// 그 틈에 입력이 끼어들지 못한다). 그사이 글이 바뀌었으면 바뀐 글로 다시 정한다.
  /// 남긴 스냅샷과 고친 순간 사이에 친 글자는 스냅샷에 없지만 ⌘Z 한 번이면 고치기 직전으로 정확히 돌아간다.
  private func rewriteOpen(
    _ id: EpisodeID, _ job: Rewrite, before: inout (text: String, snapshot: Snapshot?)?
  ) async -> RewriteOutcome? {
    guard conflicts[id] == nil else { return .conflict }
    guard var basis = textView?.string else { return nil }
    guard var found = await Self.changes(job, in: basis) else { return .unreadable }
    guard !found.changes.isEmpty else { return .nothing }
    let beforeSnapshot: Snapshot?
    do {
      beforeSnapshot = try await snapshotBefore(id, basis, count: found.changes.count, kept: found.kept, job, &before)
    } catch {
      return .snapshotFailed
    }
    while true {
      guard id == episodeID, let textView else { return nil }
      if conflicts[id] != nil { return .conflict }
      if textView.hasMarkedText() || lastInput.map({ ContinuousClock.now - $0 < Self.inputPause }) == true {
        try? await Task.sleep(for: .milliseconds(50))
        continue
      }
      // 글자 그대로 비교한다(String ==는 자모로 풀어 쓴 글도 같다고 봐서 UTF-16 자리가 어긋날 수 있다).
      guard textView.string.utf16.elementsEqual(basis.utf16) else {
        basis = textView.string
        guard let again = await Self.changes(job, in: basis) else { return .unreadable }
        found = again
        continue
      }
      guard !found.changes.isEmpty, textView.replaceOccurrences(found.changes, actionName: job.actionName) else {
        return .nothing
      }
      noteChange(id)
      if let afterMemo = job.afterMemo {
        snapshots.startReplace(
          id, kind: .replaced, text: textView.string, memo: afterMemo(found.changes.count), at: job.date)
      }
      return .done(count: found.changes.count, kept: found.kept, characters: nil, before: beforeSnapshot)
    }
  }

  private static func changes(_ job: Rewrite, in text: String) async -> (changes: [TextChange], kept: Int)? {
    let changes = job.changes
    return try? await Task.detached { try changes(text) }.value
  }

  /// 고치기 전 스냅샷. 다시 해 보는 중에 같은 글이면 또 찍지 않는다.
  private func snapshotBefore(
    _ id: EpisodeID, _ text: String, count: Int, kept: Int, _ job: Rewrite,
    _ before: inout (text: String, snapshot: Snapshot?)?
  ) async throws -> Snapshot? {
    if let before, before.text == text { return before.snapshot }
    let snapshot = try await snapshots.takeReplace(
      id, kind: job.beforeKind, text: text, memo: job.beforeMemo(count, kept), at: job.date)
    before = (text, snapshot)
    return snapshot
  }

  /// 바꾼 글을 저장 줄로 쓴다. 파일에서 읽었으면 그때의 상태, 메모리의 글이면 디스크 기준과 비교해 조건부로 쓴다.
  /// 그사이 앱 밖에서 바뀌어 쓰지 않았으면 false(다시 읽어 바꾼다).
  private func writeReplacement(_ id: EpisodeID, text: String, readVersion: DiskVersion?) async -> Bool {
    changes[id, default: 0] += 1
    let job = SaveJob(id: id, change: changes[id, default: 0], text: text)
    inFlight[id] = job
    let key = UUID()
    let write = Task { await commitReplacement(job, readVersion: readVersion) }
    running[key] = Task {
      _ = await write.value
      running[key] = nil
    }
    return await write.value
  }

  private func commitReplacement(_ job: SaveJob, readVersion: DiskVersion?) async -> Bool {
    let store = store
    let disk = disk
    defer {
      if inFlight[job.id]?.text == job.text { inFlight[job.id] = nil }
      releaseBaselineIfIdle(job.id)
    }
    do {
      let result = try await queue.save(.episode(job.id), change: job.change, writeReturning: {
        let result = try store.writeEpisode(job.text, id: job.id, ifUnchangedSince: readVersion ?? disk[job.id])
        if case .written(let version) = result { disk[job.id] = version }
        return result
      }, didWrite: { if case .written = $0 { true } else { false } })
      guard case .written = result else {
        // 바꾼 글은 버린다. 이 번호를 저장한 것으로 쳐야 고친 적 없는 회차가 "저장 안 됨"으로 남지 않는다.
        savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
        return false
      }
      savedChanges[job.id] = max(savedChanges[job.id, default: 0], job.change)
      if let failed = unsaved[job.id], failed.change <= job.change { unsaved[job.id] = nil }
      if let backed = backedUp[job.id], backed <= job.change { removeBackup(job.id) }
      settleStatus()
    } catch {
      // 다음 저장 시도도 읽은 때의 파일과 비교하게 기준을 남긴다.
      if disk[job.id] == nil, let readVersion { disk[job.id] = readVersion }
      if (unsaved[job.id]?.change ?? 0) <= job.change {
        unsaved[job.id] = job
        backUp(job)
        lastFailure = Failure(error, isBackedUp: backup != nil)
      }
      settleStatus()
    }
    return true
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
    conflicts[id] = Conflict(episodeID: id, disk: diskVersion, change: changes[id, default: 0])
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
        lastFailure = Failure(error, isBackedUp: backup != nil)
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
