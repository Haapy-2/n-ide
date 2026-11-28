import Foundation

/// Save target. Saves to the same target are processed one at a time in order.
public enum SaveTarget: Hashable, Sendable {
  case project
  case episode(EpisodeID)
  case note(NoteID)
}

public enum SaveOutcome: Equatable, Sendable {
  case written
  /// Skipped because content with a newer change number is already saved. So the latest manuscript is never reverted.
  case skippedStale
}

/// The save queue. All file writes are funneled into this one actor to:
/// 1. prevent simultaneous saves to the same file,
/// 2. prevent a lower (older) change number from overwriting a higher (newer) one,
/// 3. wait briefly and retry a few times on failure.
///
/// Change numbers are attached by the editing side (the app), incremented by 1 per target.
public actor SaveQueue {
  /// Highest change number written to file so far, per target.
  private var writtenChange: [SaveTarget: Int] = [:]
  private let retryDelays: [Duration]

  /// - Parameter retryDelays: wait before each retry after a failure. Default per PLAN.md detailed criteria (0.5 s, 1 s, 2 s).
  public init(retryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]) {
    self.retryDelays = retryDelays
  }

  /// `write` performs the actual write. If all retries fail, throws the last error (edits remain in app memory).
  public func save(
    _ target: SaveTarget, change: Int, write: @Sendable () throws -> Void
  ) async throws -> SaveOutcome {
    try await save(target, change: change, writeReturning: write) == nil ? .skippedStale : .written
  }

  /// Same as `save` but returns the write function's value. nil if skipped as an old save.
  /// (Used by episode saves to report "written" vs. "not written due to an external-change conflict".)
  /// `onRetry` is called before each retry after a failure (for the status bar's "retrying" indicator).
  /// `didWrite` tells from the returned value whether it actually wrote. Unwritten numbers don't count as saved.
  public func save<Value: Sendable>(
    _ target: SaveTarget, change: Int, writeReturning write: @Sendable () throws -> Value,
    didWrite: @Sendable (Value) -> Bool = { _ in true },
    onRetry: (@Sendable () -> Void)? = nil
  ) async throws -> Value? {
    var attempt = 0
    while true {
      // A newer save may have finished while awaiting a retry, so check again every time.
      if let written = writtenChange[target], written >= change {
        return nil
      }
      do {
        // No await in between, so within the actor no other save can slip in until one write finishes.
        let value = try write()
        if didWrite(value) { writtenChange[target] = change }
        return value
      } catch {
        guard attempt < retryDelays.count else { throw error }
        onRetry?()
        try await Task.sleep(for: retryDelays[attempt])
        attempt += 1
      }
    }
  }

  /// Highest change number saved so far for the target. nil if none yet.
  public func lastWrittenChange(for target: SaveTarget) -> Int? {
    writtenChange[target]
  }
}
