import NovelCore
import Observation

/// State of one revert sheet (PLAN ch.14 #5): checked episodes, the episode whose diff is shown, and that diff.
/// All checked by default. A diff is built only for the clicked episode, at that time (so bodies aren't held in advance).
@MainActor
@Observable
final class RevertSession: Identifiable {
  let undoable: ProjectReplace.Undoable
  var checked: Set<EpisodeID>
  /// Episode whose diff is shown (selected row)
  var focused: EpisodeID? {
    didSet { if focused != oldValue { loadPreview() } }
  }
  private(set) var preview: TextDiff?
  private(set) var isLoadingPreview = false
  /// Start of a ⇧-click range. The row whose check last changed.
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

  /// ⇧-click: set rows from the start row to this one to the start row's state.
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
