import Foundation
import NovelCore
import XCTest

/// 비교 엔진 속도. 메인 스레드 밖에서 돌지만, 스냅샷을 누르면 바로 보여야 하므로 짧아야 한다.
/// 더미 5,000자 회차를 고쳐 쓴 판(문단 몇 개 고치기·지우기·넣기)과 비교하고, 이어 붙인 10만 자도 잰다.
/// 최악: 문단이 하나도 안 겹치는 10만 자 두 개.
final class TextDiffPerformanceTests: XCTestCase {
  func testDiff() throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    let store = ProjectStore(root: URL(filePath: path, directoryHint: .isDirectory))
    let text = try store.readEpisode(try store.loadProject().episodes[0].id)
    let long = String(repeating: text + "\n", count: 20)

    report("diff_5k_ms", try samples(text, edited(text)))
    report("diff_100k_ms", try samples(long, edited(long)))
    // 모든 문단 앞에 글자를 붙여 겹치는 줄이 없게 만든다.
    let unrelated = long.split(separator: "\n", omittingEmptySubsequences: false).map { "다른 \($0)" }.joined(separator: "\n")
    report("diff_100k_unrelated_ms", try samples(long, unrelated, count: 5))
    // 줄 안 비교를 한도 없이 했을 때(한도 2,000줄을 정한 근거)
    report("diff_100k_unrelated_inline_ms", try samples(long, unrelated, count: 5, inlineLimit: .max))
  }

  /// 10문단마다 하나는 어절을 바꾸고, 하나는 지우고, 하나는 새로 넣는다.
  private func edited(_ text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var index = lines.count - 1
    while index >= 0 {
      switch index % 10 {
      case 3: lines[index] = lines[index].replacingOccurrences(of: "다.", with: "었다.")
      case 6: lines.remove(at: index)
      case 8: lines.insert("새로 넣은 문단이다.", at: index)
      default: break
      }
      index -= 1
    }
    return lines.joined(separator: "\n")
  }

  private func samples(
    _ old: String, _ new: String, count: Int = 15, inlineLimit: Int = TextDiff.defaultInlineLimit
  ) throws -> [Double] {
    let clock = ContinuousClock()
    return try (0..<count).map { _ in
      let elapsed = try clock.measure { _ = try TextDiff(old: old, new: new, inlineLimit: inlineLimit) }
      return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
  }

  private func report(_ name: String, _ values: [Double]) {
    print("NOVEL_PERF \(name) " + values.map { String(format: "%.3f", $0) }.joined(separator: ","))
  }
}
