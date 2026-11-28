import Foundation
import NovelCore
import XCTest

/// Diff engine speed. Runs off the main thread, but must be short since clicking a snapshot should show it immediately.
/// Compares a 5,000-char dummy episode with a rewritten version (a few paragraphs edited, deleted, inserted), and a concatenated 100k chars too.
/// Worst case: two 100k-char texts sharing no paragraphs.
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
    // Prefix every paragraph with a character so no lines overlap.
    let unrelated = long.split(separator: "\n", omittingEmptySubsequences: false).map { "다른 \($0)" }.joined(separator: "\n")
    report("diff_100k_unrelated_ms", try samples(long, unrelated, count: 5))
    // Unlimited in-line comparison (the basis for the 2,000-line cap)
    report("diff_100k_unrelated_inline_ms", try samples(long, unrelated, count: 5, inlineLimit: .max))
  }

  /// Every 10 paragraphs: one gets a word changed, one deleted, one newly inserted.
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
