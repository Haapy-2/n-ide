import Foundation
import NovelCore

/// 회차마다 "앱이 마지막으로 읽거나 쓴 디스크 상태". 외부 변경 판단의 기준이다.
/// 저장 줄(백그라운드)과 창 활성화 때의 확인(백그라운드), 회차 열기(메인)가 함께 쓰므로 잠금으로 지킨다.
/// 잠금은 사전을 읽고 쓰는 순간에만 잡고 파일 읽기·쓰기 동안에는 잡지 않는다. 그래서 메인 스레드가 저장을 기다리며 멈추지 않는다.
nonisolated final class DiskVersions: @unchecked Sendable {
  private let lock = NSLock()
  private var versions: [EpisodeID: DiskVersion] = [:]

  subscript(id: EpisodeID) -> DiskVersion? {
    get { lock.withLock { versions[id] } }
    set { lock.withLock { versions[id] = newValue } }
  }

  /// 지금 값이 아직 `old`일 때만 `new`로 바꾼다. 확인하는 사이에 저장이 끼어들어 기준이 바뀌었으면 false.
  func replace(_ id: EpisodeID, ifStill old: DiskVersion, with new: DiskVersion) -> Bool {
    lock.withLock {
      guard versions[id] == old else { return false }
      versions[id] = new
      return true
    }
  }
}
