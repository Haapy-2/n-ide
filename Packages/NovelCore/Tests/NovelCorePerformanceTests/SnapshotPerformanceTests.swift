import Foundation
import NovelCore
import XCTest

/// Time to take one snapshot. The app calls it off the main thread, but episode switches and quit wait for it, so it must be short.
/// On an episode with a full keep count of 50, measures "compare with latest → write → prune (delete oldest)" in one go.
final class SnapshotPerformanceTests: XCTestCase {
  func testWriteAndPrune() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    let dummy = ProjectStore(root: URL(filePath: path, directoryHint: .isDirectory))
    let text = try dummy.readEpisode(try dummy.loadProject().episodes[0].id)
    // The dummy project is left alone; a separate one is made in build/tmp.
    let root = URL(filePath: path).deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "tmp/snapshot-perf-\(UUID().uuidString)/작품.novel")
    try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let store = try ProjectStore.create(at: root, title: "측정")

    report("snapshot_5k_ms", try samples(store, text: text))
    report("snapshot_100k_ms", try samples(store, text: String(repeating: text, count: 20)))
  }

  private func samples(_ store: ProjectStore, text: String) throws -> [Double] {
    let id = EpisodeID.make()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for index in 0..<50 {
      try store.writeSnapshot(text + "\(index)", episode: id, kind: .auto, at: start.addingTimeInterval(Double(index)))
    }
    let clock = ContinuousClock()
    return try (0..<15).map { index in
      let elapsed = try clock.measure {
        try store.writeSnapshot(
          text + "new\(index)", episode: id, kind: .auto, at: start.addingTimeInterval(Double(100 + index)),
          skipIfSameAsLatest: true)
        try store.pruneSnapshots(of: id, keeping: 50)
      }
      return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
  }

  private func report(_ name: String, _ values: [Double]) {
    print("NOVEL_PERF \(name) " + values.map { String(format: "%.3f", $0) }.joined(separator: ","))
  }
}
