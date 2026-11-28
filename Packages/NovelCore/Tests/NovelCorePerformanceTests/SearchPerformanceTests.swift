import Foundation
import NovelCore
import XCTest

/// Project search (SPEC ch.8 target 0.5 s): read all 500 dummy episodes from disk and search them.
/// Search for a missing phrase so everything is read to the end (the slowest case). Common phrases stop early at 1,000.
/// The first search (first in this process) and later ones are recorded separately (SPEC ch.8 measurement method).
final class SearchPerformanceTests: XCTestCase {
  func testSearch500Episodes() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    let store = ProjectStore(root: URL(filePath: path, directoryHint: .isDirectory))
    let ids = try store.loadProject().episodes.map(\.id)
    let clock = ContinuousClock()
    var samples: [Double] = []
    for _ in 0..<8 {
      var result: ProjectSearchResult?
      let elapsed = try clock.measure {
        result = try store.search("이런문구는없다", in: ids, caseSensitive: false)
      }
      XCTAssertEqual(result?.matchCount, 0)
      XCTAssertEqual(result?.unreadable.count, 0)
      samples.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    report("search_500_first_ms", [samples[0]])
    report("search_500_ms", Array(samples.dropFirst()))

    // Only the first 10 dummy episodes are 5,000 chars, ~200k chars total. Search time for a project with all 500 episodes at 5,000 chars (2.5M chars)
    // is measured separately: a 5,000-char episode text is passed as 500 episodes' texts, timing only the search without file reads.
    let text = try store.readEpisode(ids[0])
    let texts = Dictionary(uniqueKeysWithValues: ids.map { ($0, text) })
    var full: [Double] = []
    for _ in 0..<5 {
      let elapsed = try clock.measure { _ = try store.search("이런문구는없다", in: ids, texts: texts, caseSensitive: false) }
      full.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    report("search_500x5k_ms", full)
  }

  private func report(_ name: String, _ values: [Double]) {
    print("NOVEL_PERF \(name) " + values.map { String(format: "%.3f", $0) }.joined(separator: ","))
  }
}
