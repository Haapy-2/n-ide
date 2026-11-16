import Foundation
import NovelCore
import XCTest

/// 스냅샷 한 번 찍는 시간 (11a). 앱은 메인 스레드 밖에서 부르지만, 회차 전환·앱 종료 때 기다리므로 짧아야 한다.
/// 보관 개수 50개가 꽉 찬 회차에 "마지막 것과 비교 → 쓰기 → 정리(가장 오래된 것 지우기)"를 한 번에 잰다.
final class SnapshotPerformanceTests: XCTestCase {
  func testWriteAndPrune() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    let dummy = ProjectStore(root: URL(filePath: path, directoryHint: .isDirectory))
    let text = try dummy.readEpisode(try dummy.loadProject().episodes[0].id)
    // 더미 작품은 건드리지 않고 build/tmp에 따로 만든다.
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
