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
  @ObservationIgnored private var projectChange = 0
  /// 파일을 휴지통으로 옮긴다. 테스트에서는 진짜 휴지통 대신 다른 곳으로 옮기도록 바꿔 끼운다.
  @ObservationIgnored private let moveToTrash: @Sendable (URL) throws -> Void

  init(
    project: ProjectFile, store: ProjectStore, queue: SaveQueue = SaveQueue(),
    autosaveDelay: Duration = .seconds(1),
    moveToTrash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
  ) {
    self.project = project
    self.store = store
    self.queue = queue
    self.moveToTrash = moveToTrash
    autosaver = EpisodeAutosaver(store: store, queue: queue, delay: autosaveDelay)
  }

  var episodes: [EpisodeMeta] { project.episodes }

  func episode(_ id: EpisodeID) -> EpisodeMeta? {
    project.episodes.first { $0.id == id }
  }

  // MARK: - 회차 바꾸기

  /// 새 회차를 `after` 바로 뒤(없으면 맨 끝)에 만든다. 빈 본문 파일을 먼저 쓰고 목록에 넣는다.
  @discardableResult
  func addEpisode(after: EpisodeID? = nil) async throws -> EpisodeID {
    let episode = EpisodeMeta(title: "", goal: project.settings.defaultEpisodeGoal)
    let store = store
    let id = episode.id
    // 본문 파일이 먼저 있어야 목록에만 있고 파일은 없는 회차가 생기지 않는다.
    try await Task.detached { try store.writeEpisode("", id: id) }.value
    let index = after.flatMap { id in project.episodes.firstIndex { $0.id == id } }.map { $0 + 1 }
    project.episodes.insert(episode, at: index ?? project.episodes.endIndex)
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
    project.episodes = episodes
    return Task { await saveProject() }
  }

  /// 회차를 휴지통으로 옮긴다. 휴지통으로 못 옮기면 아무것도 바꾸지 않고 오류를 던진다(영구 삭제로 대신하지 않음).
  func trashEpisode(_ id: EpisodeID) async throws {
    guard let index = project.episodes.firstIndex(where: { $0.id == id }) else { return }
    // 지우기 전에 고친 내용을 저장해 둔다. 휴지통에서 꺼냈을 때 마지막 내용이 들어 있도록.
    await autosaver.flush()
    let file = store.layout.episodeFile(id)
    let moveToTrash = moveToTrash
    try await Task.detached {
      if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { try moveToTrash(file) }
    }.value
    autosaver.forget(episode: id)
    project.episodes.remove(at: index)
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
