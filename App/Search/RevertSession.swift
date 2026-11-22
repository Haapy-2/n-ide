import NovelCore
import Observation

/// 되돌리기 창 하나의 상태(PLAN 14장 5번): 체크한 회차, 비교를 보는 회차, 그 비교.
/// 체크는 기본으로 모두. 비교는 누른 회차만 그때 만든다(본문을 미리 들고 있지 않게).
@MainActor
@Observable
final class RevertSession: Identifiable {
  let undoable: ProjectReplace.Undoable
  var checked: Set<EpisodeID>
  /// 비교를 보는 회차(목록에서 고른 줄)
  var focused: EpisodeID? {
    didSet { if focused != oldValue { loadPreview() } }
  }
  private(set) var preview: TextDiff?
  private(set) var isLoadingPreview = false
  /// ⇧클릭 범위의 시작. 마지막으로 체크를 바꾼 줄.
  @ObservationIgnored private var anchor: EpisodeID?
  @ObservationIgnored private let replace: ProjectReplace
  @ObservationIgnored private var previewTask: Task<Void, Never>?

  var id: ProjectReplace.Record.ID { undoable.record.id }
  var candidates: [ProjectReplace.Candidate] { undoable.candidates }

  init(_ undoable: ProjectReplace.Undoable, replace: ProjectReplace) {
    self.undoable = undoable
    self.replace = replace
    checked = Set(undoable.candidates.map(\.id))
    focused = undoable.candidates.first?.id
    loadPreview()
  }

  func toggle(_ id: EpisodeID) {
    if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    anchor = id
  }

  /// ⇧클릭: 시작 줄부터 이 줄까지를 시작 줄과 같은 상태로.
  func extend(to id: EpisodeID) {
    let ids = candidates.map(\.id)
    guard let anchor, let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: id) else {
      toggle(id)
      return
    }
    let range = ids[min(from, to)...max(from, to)]
    if checked.contains(anchor) { checked.formUnion(range) } else { checked.subtract(range) }
  }

  func checkAll() { checked = Set(candidates.map(\.id)) }
  func uncheckAll() { checked.removeAll() }

  private func loadPreview() {
    previewTask?.cancel()
    preview = nil
    isLoadingPreview = false
    guard let focused else { return }
    isLoadingPreview = true
    let record = undoable.record
    previewTask = Task {
      let diff = await replace.preview(record, focused)
      guard !Task.isCancelled else { return }
      preview = diff
      isLoadingPreview = false
    }
  }
}
