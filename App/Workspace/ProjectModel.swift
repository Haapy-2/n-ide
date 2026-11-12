import Foundation
import NovelCore
import Observation

/// 열린 작품 하나의 회차 목록과 그 저장. 회차 추가·이름 변경·휴지통으로 보내기·순서 변경을 맡는다.
/// `project.json` 저장은 본문 자동 저장과 같은 저장 줄(`SaveQueue`)로 보내 순서를 지킨다.
@MainActor
@Observable
final class ProjectModel {
  private(set) var project: ProjectFile
  /// `project.json` 저장이 끝내 실패했을 때의 설명. 화면에 띄운다.
  var errorMessage: String?

  let store: ProjectStore
  @ObservationIgnored let queue: SaveQueue
  @ObservationIgnored let autosaver: EpisodeAutosaver
  @ObservationIgnored let counter: CharacterCounter
  @ObservationIgnored private var projectChange = 0
  /// 파일을 휴지통으로 옮기고 휴지통 안의 새 위치를 돌려준다(되돌리기 때 다시 꺼내려고).
  /// 테스트에서는 진짜 휴지통 대신 다른 곳으로 옮기도록 바꿔 끼운다.
  @ObservationIgnored private let moveToTrash: @Sendable (URL) throws -> URL
  /// 글자 수만 바뀌었을 때 project.json 저장을 미뤄 묶는 시간(docs/PERFORMANCE.md 2장).
  @ObservationIgnored private let countSaveDelay: Duration
  @ObservationIgnored private var countSave: Task<Void, Never>?

  init(
    project: ProjectFile, store: ProjectStore, queue: SaveQueue = SaveQueue(),
    autosaveDelay: Duration = .seconds(1),
    countDelay: Duration = .milliseconds(200),
    countSaveDelay: Duration = .seconds(3),
    moveToTrash: @escaping @Sendable (URL) throws -> URL = ProjectModel.systemTrash
  ) {
    self.project = project
    self.store = store
    self.queue = queue
    self.moveToTrash = moveToTrash
    self.countSaveDelay = countSaveDelay
    autosaver = EpisodeAutosaver(store: store, queue: queue, delay: autosaveDelay)
    counter = CharacterCounter(interval: countDelay)
    counter.onCount = { [weak self] id, count in self?.recordCount(count, for: id) }
  }

  var episodes: [EpisodeMeta] { project.episodes }

  func episode(_ id: EpisodeID) -> EpisodeMeta? {
    project.episodes.first { $0.id == id }
  }

  // MARK: - 회차 바꾸기

  /// 새 회차를 `after` 바로 뒤(없으면 맨 끝)에 만든다. 빈 본문 파일을 먼저 쓰고 목록에 넣는다.
  /// `undoManager`를 주면 ⌘Z로 방금 만든 회차를 휴지통으로 보낼 수 있다(⇧⌘Z로 다시 꺼냄).
  @discardableResult
  func addEpisode(after: EpisodeID? = nil, undoManager: UndoManager? = nil) async throws -> EpisodeID {
    let episode = EpisodeMeta(title: "", goal: project.settings.defaultEpisodeGoal)
    let store = store
    let id = episode.id
    // 본문 파일이 먼저 있어야 목록에만 있고 파일은 없는 회차가 생기지 않는다.
    try await Task.detached { try store.writeEpisode("", id: id) }.value
    let index = after.flatMap { id in project.episodes.firstIndex { $0.id == id } }.map { $0 + 1 }
    let insertAt = index ?? project.episodes.endIndex
    project.episodes.insert(episode, at: insertAt)
    registerUndoByTrashing(TrashRecord(episode: episode, index: insertAt), actionName: "새 회차", undoManager: undoManager)
    await saveProject()
    return id
  }

  /// 이름 변경. `undoManager`를 주면 ⌘Z로 되돌릴 수 있다.
  func rename(_ id: EpisodeID, to title: String, undoManager: UndoManager? = nil) async {
    guard let index = project.episodes.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard project.episodes[index].title != trimmed else { return }
    var episodes = project.episodes
    episodes[index].title = trimmed
    await replaceEpisodes(with: episodes, actionName: "이름 변경", undoManager: undoManager).value
  }

  /// 회차 목표 글자 수. `undoManager`를 주면 ⌘Z로 되돌릴 수 있다.
  func setGoal(_ id: EpisodeID, to goal: Int, undoManager: UndoManager? = nil) async {
    guard goal > 0, let index = project.episodes.firstIndex(where: { $0.id == id }),
      project.episodes[index].goal != goal
    else { return }
    var episodes = project.episodes
    episodes[index].goal = goal
    await replaceEpisodes(with: episodes, actionName: "목표 글자 수", undoManager: undoManager).value
  }

  /// 작품 기본 목표 글자 수(새 회차에 쓰는 값, project.json의 작품별 설정). `undoManager`를 주면 ⌘Z로 되돌릴 수 있다.
  /// 되돌리기 기록은 그 자리에서(동기로) 한다. 회차 목표와 같은 순간에 부르면 ⌘Z 한 번에 둘 다 되돌아간다.
  @discardableResult
  func setDefaultEpisodeGoal(_ goal: Int, undoManager: UndoManager? = nil) -> Task<Void, Never> {
    let previous = project.settings.defaultEpisodeGoal
    guard goal > 0, goal != previous else { return Task {} }
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated { model.setDefaultEpisodeGoal(previous, undoManager: undoManager) }
    }
    undoManager?.setActionName("목표 글자 수")
    project.settings.defaultEpisodeGoal = goal
    return Task { await saveProject() }
  }

  /// 드래그로 순서 바꾸기. `undoManager`를 주면 ⌘Z로 직전 순서로 되돌릴 수 있다.
  func moveEpisodes(fromOffsets source: IndexSet, toOffset destination: Int, undoManager: UndoManager? = nil) async {
    var episodes = project.episodes
    episodes.move(fromOffsets: source, toOffset: destination)
    guard episodes != project.episodes else { return }
    await replaceEpisodes(with: episodes, actionName: "순서 변경", undoManager: undoManager).value
  }

  /// 회차 목록(순서·제목)을 통째로 바꾸고 저장을 시작한다. 되돌리기에는 바꾸기 전 목록을 기록한다.
  /// 되돌리기 처리 안에서 다시 이 함수를 부르므로 다시 실행(⇧⌘Z)이 자동으로 쌓인다.
  /// 기록은 반드시 그 자리에서(동기로) 해야 UndoManager가 되돌리기/다시 실행을 제대로 구분한다.
  /// 회차 목록만 바꾸고 파일은 건드리지 않으므로 되돌려도 본문에는 영향이 없다.
  @discardableResult
  private func replaceEpisodes(
    with episodes: [EpisodeMeta], actionName: String, undoManager: UndoManager?
  ) -> Task<Void, Never> {
    let previous = project.episodes
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated {
        // 그 사이 회차가 추가·삭제됐으면 그 변화를 덮어쓰지 않도록, 같은 회차들일 때만 되돌린다.
        guard Set(model.project.episodes.map(\.id)) == Set(previous.map(\.id)) else { return }
        model.replaceEpisodes(with: previous, actionName: actionName, undoManager: undoManager)
      }
    }
    undoManager?.setActionName(actionName)
    // 글자 수는 되돌리기 대상이 아니다. 기록해 둔 옛 목록의 글자 수가 아니라 지금 값을 이어받는다.
    let counts = Dictionary(project.episodes.map { ($0.id, $0.characterCount) }, uniquingKeysWith: { first, _ in first })
    project.episodes = episodes.map { episode in
      var episode = episode
      if let count = counts[episode.id] { episode.characterCount = count }
      return episode
    }
    return Task { await saveProject() }
  }

  /// 회차를 휴지통으로 옮긴다. 휴지통으로 못 옮기면 아무것도 바꾸지 않고 오류를 던진다(영구 삭제로 대신하지 않음).
  /// `undoManager`를 주면 ⌘Z로 휴지통에서 꺼내 원래 자리에 되돌릴 수 있다.
  func trashEpisode(_ id: EpisodeID, undoManager: UndoManager? = nil) async throws {
    guard let index = project.episodes.firstIndex(where: { $0.id == id }) else { return }
    let record = TrashRecord(episode: project.episodes[index], index: index)
    try await moveToTrash(record)
    registerUndoByRestoring(record, actionName: "휴지통으로 이동", undoManager: undoManager)
  }

  // MARK: - 휴지통과 되돌리기

  /// 휴지통으로 보낸(또는 보낼) 회차 하나의 기록. 되돌리기와 다시 실행이 같은 기록을 주고받는다.
  final class TrashRecord {
    let episode: EpisodeMeta
    let index: Int
    /// 휴지통 안의 위치. 휴지통에 있을 때만 값이 있다.
    var trashedURL: URL?

    init(episode: EpisodeMeta, index: Int) {
      self.episode = episode
      self.index = index
    }
  }

  private func moveToTrash(_ record: TrashRecord) async throws {
    let id = record.episode.id
    // 지우기 전에 고친 내용을 저장해 둔다. 휴지통에서 꺼냈을 때 마지막 내용이 들어 있도록.
    await autosaver.flush()
    let file = store.layout.episodeFile(id)
    let moveToTrash = moveToTrash
    record.trashedURL = try await Task.detached {
      FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? try moveToTrash(file) : nil
    }.value
    autosaver.forget(episode: id)
    project.episodes.removeAll { $0.id == id }
    await saveProject()
  }

  /// 휴지통에서 꺼내 원래 자리(그사이 목록이 줄었으면 맨 끝)에 다시 넣는다. 같은 이름의 파일이 이미 있으면 덮어쓰지 않는다.
  private func restoreFromTrash(_ record: TrashRecord) async throws {
    guard !project.episodes.contains(where: { $0.id == record.episode.id }) else { return }
    if let trashed = record.trashedURL {
      let destination = store.layout.episodeFile(record.episode.id)
      try await Task.detached { try FileManager.default.moveItem(at: trashed, to: destination) }.value
      record.trashedURL = nil
    }
    project.episodes.insert(record.episode, at: min(record.index, project.episodes.count))
    await saveProject()
  }

  // 되돌리기 기록은 반드시 그 자리에서(동기로) 한다. 파일 옮기기는 그 뒤에 Task로 한다.
  // 그래야 UndoManager가 되돌리기와 다시 실행을 제대로 구분해 쌓는다.

  /// ⌘Z를 누르면 이 회차를 휴지통으로 보내도록 기록한다(새 회차 되돌리기, 휴지통 꺼내기의 다시 실행).
  private func registerUndoByTrashing(_ record: TrashRecord, actionName: String, undoManager: UndoManager?) {
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated {
        model.registerUndoByRestoring(record, actionName: actionName, undoManager: undoManager)
        Task { await model.runFileUndo { try await model.moveToTrash(record) } }
      }
    }
    undoManager?.setActionName(actionName)
  }

  /// ⌘Z를 누르면 이 회차를 휴지통에서 꺼내도록 기록한다(휴지통으로 이동 되돌리기, 새 회차의 다시 실행).
  private func registerUndoByRestoring(_ record: TrashRecord, actionName: String, undoManager: UndoManager?) {
    undoManager?.registerUndo(withTarget: self) { model in
      MainActor.assumeIsolated {
        model.registerUndoByTrashing(record, actionName: actionName, undoManager: undoManager)
        Task { await model.runFileUndo { try await model.restoreFromTrash(record) } }
      }
    }
    undoManager?.setActionName(actionName)
  }

  private func runFileUndo(_ work: () async throws -> Void) async {
    do {
      try await work()
    } catch {
      errorMessage = "되돌리지 못했어요. 파일은 그대로 두었어요. \(error.localizedDescription)"
    }
  }

  nonisolated static func systemTrash(_ url: URL) throws -> URL {
    var resulting: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    guard let resulting else { throw CocoaError(.fileWriteUnknown) }
    return resulting as URL
  }

  // MARK: - 글자 수

  /// 센 글자 수를 회차 목록에 적는다. 바뀌었을 때만 적고, project.json 저장은 미뤄서 묶는다.
  /// (입력이 멈출 때마다 쓰지 않으려는 것. 저장 전에 앱이 꺼져도 그 회차를 다시 열면 다시 센다.)
  func recordCount(_ count: CharacterCount, for id: EpisodeID) {
    guard let index = project.episodes.firstIndex(where: { $0.id == id }),
      project.episodes[index].characterCount != count
    else { return }
    project.episodes[index].characterCount = count
    guard countSave == nil else { return }
    countSave = Task { [countSaveDelay] in
      try? await Task.sleep(for: countSaveDelay)
      guard !Task.isCancelled else { return }
      countSave = nil
      await saveProject()
    }
  }

  /// 미뤄 둔 글자 수 저장을 지금 한다(창을 닫을 때).
  func saveCountsNow() async {
    guard let task = countSave else { return }
    task.cancel()
    countSave = nil
    await saveProject()
  }

  // MARK: - 저장

  private func saveProject() async {
    projectChange += 1
    let change = projectChange
    let snapshot = project
    let store = store
    do {
      _ = try await queue.save(.project, change: change) { try store.saveProject(snapshot) }
      errorMessage = nil
    } catch {
      let reason = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      errorMessage = "회차 목록(project.json)을 저장하지 못했어요. \(reason)"
    }
  }
}
