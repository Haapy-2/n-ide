import Foundation
import NovelCore

/// Per episode, "the disk state the app last read or wrote". The baseline for external-change detection.
/// Shared by the save queue (background), activation checks (background) and episode opening (main), so it's lock-protected.
/// The lock is held only while touching the dictionary, never during file I/O, so the main thread never stalls waiting on a save.
nonisolated final class DiskVersions: @unchecked Sendable {
  private let lock = NSLock()
  private var versions: [EpisodeID: DiskVersion] = [:]

  subscript(id: EpisodeID) -> DiskVersion? {
    get { lock.withLock { versions[id] } }
    set { lock.withLock { versions[id] = newValue } }
  }

  /// Change to `new` only if the current value is still `old`. False if a save slipped in and moved the baseline meanwhile.
  func replace(_ id: EpisodeID, ifStill old: DiskVersion, with new: DiskVersion) -> Bool {
    lock.withLock {
      guard versions[id] == old else { return false }
      versions[id] = new
      return true
    }
  }
}
