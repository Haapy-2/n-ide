import Foundation
import NovelCore
import XCTest

/// 작품 전체 검색 (SPEC 8장 목표 0.5초): 더미 500회차를 디스크에서 읽어 모두 찾는다.
/// 없는 문구로 찾아 끝까지 다 읽게 한다(가장 오래 걸리는 경우). 많이 나오는 문구는 1,000개에서 일찍 멈춘다.
/// 처음 찾기(이 프로세스에서 처음)와 두 번째 이후를 따로 적는다(SPEC 8장 측정 방법).
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

    // 더미는 앞 10화만 5,000자라 모두 합쳐 약 20만 자다. 500회차가 모두 5,000자(250만 자)인 작품의 찾기 시간을
    // 따로 본다: 5,000자 회차 글을 500개 회차의 글로 넘겨 파일 읽기 없이 찾기만 잰다.
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
