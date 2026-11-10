import Foundation

/// 저장할 대상. 같은 대상에 대한 저장은 순서대로 하나씩만 처리된다.
public enum SaveTarget: Hashable, Sendable {
  case project
  case episode(EpisodeID)
  case note(NoteID)
}

/// 저장 요청의 결과.
public enum SaveOutcome: Equatable, Sendable {
  /// 파일에 썼다.
  case written
  /// 이미 더 새 변경 번호의 내용이 저장되어 있어서 건너뛰었다. 최신 원고를 되돌리지 않기 위해서다.
  case skippedStale
}

/// 저장 줄. 모든 파일 쓰기를 이 actor 하나로 모아서:
/// 1. 같은 파일에 대한 저장이 동시에 일어나지 않게 하고,
/// 2. 변경 번호가 더 낮은(옛) 저장이 더 높은(새) 저장을 덮어쓰지 못하게 하고,
/// 3. 실패하면 잠깐 기다렸다 몇 번 다시 시도한다.
///
/// 변경 번호는 편집하는 쪽(앱)이 대상마다 1씩 올려서 붙인다.
public actor SaveQueue {
  /// 대상별로 지금까지 파일에 쓴 가장 높은 변경 번호.
  private var writtenChange: [SaveTarget: Int] = [:]
  private let retryDelays: [Duration]

  /// - Parameter retryDelays: 실패 후 다시 시도하기 전 기다리는 시간. 기본값은 PLAN.md 세부 기준(0.5초, 1초, 2초).
  public init(retryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]) {
    self.retryDelays = retryDelays
  }

  /// `write`로 실제 쓰기를 한다. 재시도까지 모두 실패하면 마지막 오류를 던진다(편집 내용은 앱 메모리에 그대로 있다).
  public func save(
    _ target: SaveTarget, change: Int, write: @Sendable () throws -> Void
  ) async throws -> SaveOutcome {
    var attempt = 0
    while true {
      // 재시도를 기다리는 동안(await) 더 새 저장이 끝났을 수 있으므로 매번 다시 확인한다.
      if let written = writtenChange[target], written >= change {
        return .skippedStale
      }
      do {
        // 이 사이에는 await가 없어서, actor 안에서 쓰기 하나가 끝날 때까지 다른 저장이 끼어들지 못한다.
        try write()
        writtenChange[target] = change
        return .written
      } catch {
        guard attempt < retryDelays.count else { throw error }
        try await Task.sleep(for: retryDelays[attempt])
        attempt += 1
      }
    }
  }

  /// 대상이 지금까지 저장된 가장 높은 변경 번호. 아직 없으면 nil.
  public func lastWrittenChange(for target: SaveTarget) -> Int? {
    writtenChange[target]
  }
}
