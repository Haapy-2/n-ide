import AppKit
import Darwin
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// Tells whether memory accumulates (leaks) while switching episodes, or grows once and stops (Scripts/perf.sh only, skipped normally).
/// Shows sidebar + editor (with autosaver, count, snapshots), loops over 500 episodes three times, then opens and closes a 100k-char episode three times.
/// Each loop records actual usage (phys_footprint) together with what malloc really holds (size_in_use).
/// malloc doesn't immediately return freed memory to the OS, so it lingers in footprint for a while.
/// So "accumulating" is judged by size_in_use.
@MainActor
final class MemoryGrowthTests: XCTestCase {
  func testEpisodeSwitchMemory() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    // Works on a copy of the dummy, since counts get saved to project.json and a 100k-char episode is added (the original dummy stays).
    let source = URL(filePath: path, directoryHint: .isDirectory)
    let root = source.deletingLastPathComponent().appending(path: "memory-check.novel", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.copyItem(at: source, to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProjectStore(root: root)
    let project = try store.loadProject()
    let ids = project.episodes.map(\.id)
    let bigID = ids[10]
    try store.writeEpisode(String(repeating: try store.readEpisode(ids[0]), count: 20), id: bigID)

    let model = ProjectModel(project: project, store: store)
    let selection = SelectionBox(ids[0])
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SwitchHost(model: model, selection: selection))
    window.orderFront(nil)
    defer { window.close() }
    settle(1)

    var lines = ["start=" + Self.reading()]
    for pass in 1...3 {
      for id in ids where id != bigID {
        selection.id = id
        RunLoop.main.run(mode: .default, before: Date())
        window.displayIfNeeded()
      }
      settle(1)
      lines.append("pass\(pass)=" + Self.reading())
    }
    for round in 1...3 {
      selection.id = bigID
      settle(0.5)
      lines.append("big\(round)=" + Self.reading())
      selection.id = ids[0]
      settle(0.5)
      lines.append("away\(round)=" + Self.reading())
    }
    print("NOVEL_PERF memory_switch " + lines.joined(separator: " "))
  }

  /// "footprint/malloc" (MB)
  private static func reading() -> String {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return String(format: "%.1f/%.1f", Double(info.phys_footprint) / 1_048_576, Double(stats.size_in_use) / 1_048_576)
  }

  private func settle(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
  }
}

@MainActor
@Observable
private final class SelectionBox {
  var id: EpisodeID?
  init(_ id: EpisodeID?) { self.id = id }
}

/// Same structure as the workspace (sidebar + editor). The workspace's selection is internal, so this is built separately to change it from outside.
private struct SwitchHost: View {
  let model: ProjectModel
  @Bindable var selection: SelectionBox

  var body: some View {
    NavigationSplitView {
      EpisodeList(episodes: model.project.episodes, selection: $selection.id, marked: .constant([]), measuredInset: .constant(nil), countBox: { model.countBox(for: $0) })
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)  // Same width as the workspace
    } detail: {
      if let id = selection.id {
        EpisodeEditorPane(
          autosaver: model.autosaver, counter: model.counter, episodeID: id, goal: 5_000,
          knownCount: { model.countBox(for: id).value })
      }
    }
  }
}
