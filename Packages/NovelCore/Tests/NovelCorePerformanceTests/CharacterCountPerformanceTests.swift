import Foundation
import NovelCore
import XCTest

/// Full character count speed (SPEC ch.8: measure first whether incremental counting is needed).
/// Measures 5,000 chars using a 5,000-char dummy episode body, and 100k chars made by concatenating it.
/// Also measures a string bridged from NSString (`textView.string`), as in the editor.
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
    // String taken from NSTextView's text storage (wrapping a UTF-16 NSString). Includes the time to convert to a Swift string.
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
