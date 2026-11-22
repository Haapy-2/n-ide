import AppKit
import Darwin
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// 회차를 오갈 때 메모리가 쌓이는지(새는지), 한 번 늘고 멈추는지 가린다 (Scripts/perf.sh 전용, 평소에는 건너뛴다).
/// 사이드바 + 편집 영역(자동 저장기·글자 수·스냅샷 포함)을 띄우고 500회차를 세 바퀴 돈 뒤 10만 자 회차를 세 번 열고 닫는다.
/// 바퀴마다 실제 사용량(phys_footprint)과 malloc이 실제로 쥐고 있는 양(size_in_use)을 함께 찍는다.
/// 해제한 메모리도 malloc이 운영체제에 바로 돌려주지 않아 footprint에는 한동안 남는다.
/// 그래서 "쌓이는지"는 size_in_use로 본다.
@MainActor
final class MemoryGrowthTests: XCTestCase {
  func testEpisodeSwitchMemory() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    // 더미를 복사해 쓴다. 글자 수가 project.json에 저장되고 10만 자 회차를 하나 넣기 때문(원래 더미는 그대로 둔다).
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

/// 작업 공간과 같은 짜임(사이드바 + 편집 영역). 작업 공간의 선택은 안에 숨어 있어 밖에서 바꿀 수 있게 따로 꾸렸다.
private struct SwitchHost: View {
  let model: ProjectModel
  @Bindable var selection: SelectionBox

  var body: some View {
    NavigationSplitView {
      EpisodeList(episodes: model.project.episodes, selection: $selection.id, marked: .constant([]), measuredInset: .constant(nil), countBox: { model.countBox(for: $0) })
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)  // 작업 공간과 같은 폭
    } detail: {
      if let id = selection.id {
        EpisodeEditorPane(
          autosaver: model.autosaver, counter: model.counter, episodeID: id, goal: 5_000,
          knownCount: { model.countBox(for: id).value })
      }
    }
  }
}
