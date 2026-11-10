import Foundation
import NovelCore
import XCTest

/// 500회차 작품 열기: `project.json` 읽기(복구 확인 포함) + 첫 회차 본문 읽기.
/// 더미 작품은 Scripts/perf.sh가 build/perf/에 미리 만든다. 경로는 NOVEL_PERF_PROJECT로 받는다.
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
