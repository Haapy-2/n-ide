import Foundation
import NovelCore
import XCTest

/// 글자 수 전체 계산 속도 (SPEC 8장: 증분 계산이 필요한지 먼저 잰다).
/// 더미 작품의 5,000자 회차 본문으로 5,000자와, 그것을 이어 붙인 10만 자를 잰다.
/// 편집기에서처럼 NSString에서 넘어온 문자열(`textView.string`)도 함께 잰다.
final class CharacterCountPerformanceTests: XCTestCase {
  func testCountFullText() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    let store = ProjectStore(root: URL(filePath: path, directoryHint: .isDirectory))
    let project = try store.loadProject()
    let text = try store.readEpisode(project.episodes[0].id)
    let long = String(repeating: text, count: 20)
    report("count_5k_ms", samples { _ = CharacterCount(counting: text) })
    report("count_100k_ms", samples { _ = CharacterCount(counting: long) })
    // NSTextView의 텍스트 저장소에서 꺼낸 문자열(UTF-16 NSString을 감싼 것). Swift 문자열로 바꾸는 시간까지 들어간다.
    let bridged = NSMutableString(string: long).copy() as! String
    report("count_100k_bridged_ms", samples { _ = CharacterCount(counting: bridged) })
  }

  private func samples(_ work: () -> Void) -> [Double] {
    let clock = ContinuousClock()
    return (0..<15).map { _ in
      let elapsed = clock.measure(work)
      return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
  }

  private func report(_ name: String, _ values: [Double]) {
    print("NOVEL_PERF \(name) " + values.map { String(format: "%.3f", $0) }.joined(separator: ","))
  }
}
