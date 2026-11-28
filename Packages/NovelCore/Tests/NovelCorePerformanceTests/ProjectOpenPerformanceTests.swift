import Foundation
import NovelCore
import XCTest

/// Opening a 500-episode project: read `project.json` (including the recovery check) + read the first episode body.
/// The dummy project is prebuilt in build/perf/ by Scripts/perf.sh. The path comes from NOVEL_PERF_PROJECT.
final class ProjectOpenPerformanceTests: XCTestCase {
  private var projectURL: URL {
    get throws {
      guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
        throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
      }
      return URL(filePath: path, directoryHint: .isDirectory)
    }
  }

  private var options: XCTMeasureOptions {
    let options = XCTMeasureOptions()
    options.iterationCount = 7
    return options
  }

  func testOpen500EpisodeProject() throws {
    let store = ProjectStore(root: try projectURL)
    measure(metrics: [XCTClockMetric()], options: options) {
      let (project, _) = try! store.open()
      _ = try! store.readEpisode(project.episodes[0].id)
    }
  }
}
