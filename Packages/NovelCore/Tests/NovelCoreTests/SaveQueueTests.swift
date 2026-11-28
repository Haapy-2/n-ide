import Foundation
import Synchronization
import Testing
@testable import NovelCore

/// The save queue. "An old save finishing late reverting the latest manuscript" must never happen (SPEC ch.6).
struct SaveQueueTests {
  private let fast: [Duration] = [.milliseconds(5), .milliseconds(5), .milliseconds(5)]

  /// Reproduces exactly the case where an old save (change 1) arrives after a new save (change 2).
  @Test func lateOldSaveDoesNotOverwriteNewerText() async throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    let queue = SaveQueue(retryDelays: fast)

    let newer = try await queue.save(.episode(id), change: 2) { try store.writeEpisode("새 원고", id: id) }
    let older = try await queue.save(.episode(id), change: 1) { try store.writeEpisode("옛 원고", id: id) }

    #expect(newer == .written)
    #expect(older == .skippedStale)
    #expect(try store.readEpisode(id) == "새 원고")
  }

  /// If the write function reports "not written" (external-change conflict), that number doesn't count as saved.
  /// Counting it would skip the next save with the same number as "old" and even discard the manuscript held in memory.
  @Test func writeThatDidNotHappenIsNotCounted() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let id = EpisodeID.make()
    let skipped = try await queue.save(.episode(id), change: 3, writeReturning: { false }, didWrite: { $0 })
    #expect(skipped == false)
    #expect(await queue.lastWrittenChange(for: .episode(id)) == nil)
    let again = try await queue.save(.episode(id), change: 3, writeReturning: { true }, didWrite: { $0 })
    #expect(again == true, "같은 번호라도 앞에서 실제로 쓰지 않았으면 쓴다")
  }

  @Test func sameChangeNumberIsNotWrittenTwice() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let id = EpisodeID.make()
    #expect(try await queue.save(.episode(id), change: 3) {} == .written)
    #expect(try await queue.save(.episode(id), change: 3) {} == .skippedStale)
  }

  @Test func manyConcurrentSavesEndWithHighestChange() async throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "x")
    let id = EpisodeID.make()
    let queue = SaveQueue(retryDelays: fast)

    await withTaskGroup(of: Void.self) { group in
      for change in (1...100).shuffled() {
        group.addTask {
          _ = try? await queue.save(.episode(id), change: change) {
            try store.writeEpisode("변경 \(change)", id: id)
          }
        }
      }
    }

    #expect(try store.readEpisode(id) == "변경 100")
    #expect(await queue.lastWrittenChange(for: .episode(id)) == 100)
  }

  @Test func differentTargetsDoNotBlockEachOther() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let a = EpisodeID.make()
    let b = EpisodeID.make()
    #expect(try await queue.save(.episode(a), change: 5) {} == .written)
    // Other episodes have separate numbering.
    #expect(try await queue.save(.episode(b), change: 1) {} == .written)
    #expect(try await queue.save(.project, change: 1) {} == .written)
  }

  @Test func retriesAfterTemporaryFailure() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let attempts = Mutex(0)

    let outcome = try await queue.save(.project, change: 1) {
      let count = attempts.withLock { value -> Int in
        value += 1
        return value
      }
      if count < 3 { throw ProjectError.writeFailed(URL(filePath: "/x"), reason: "잠깐 실패") }
    }

    #expect(outcome == .written)
    #expect(attempts.withLock { $0 } == 3)
  }

  /// Reports before each retry (status bar "retrying"). Not called if the first attempt succeeds.
  @Test func reportsEachRetry() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let attempts = Mutex(0)
    let retries = Mutex(0)

    _ = try await queue.save(.project, change: 1, writeReturning: {
      let count = attempts.withLock { value -> Int in
        value += 1
        return value
      }
      if count < 3 { throw ProjectError.writeFailed(URL(filePath: "/x"), reason: "잠깐 실패") }
    }, onRetry: { retries.withLock { $0 += 1 } })
    _ = try await queue.save(.project, change: 2, writeReturning: {}, onRetry: { retries.withLock { $0 += 100 } })

    #expect(retries.withLock { $0 } == 2)
  }

  @Test func givesUpAfterRetriesAndReportsError() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let attempts = Mutex(0)

    await #expect(throws: ProjectError.self) {
      try await queue.save(.project, change: 1) {
        attempts.withLock { $0 += 1 }
        throw ProjectError.writeFailed(URL(filePath: "/x"), reason: "디스크 꽉 참")
      }
    }
    // First attempt + 3 retries
    #expect(attempts.withLock { $0 } == 4)
    #expect(await queue.lastWrittenChange(for: .project) == nil)
  }

  /// If a new save finishes while an old failed save waits to retry, the old save gives up instead of writing again.
  @Test func retryingOldSaveYieldsToNewerSave() async throws {
    let queue = SaveQueue(retryDelays: [.milliseconds(200), .milliseconds(200), .milliseconds(200)])
    let content = Mutex("")
    let oldFailedOnce = Mutex(false)

    async let old = queue.save(.project, change: 1) {
      let shouldFail = oldFailedOnce.withLock { failed -> Bool in
        defer { failed = true }
        return !failed
      }
      if shouldFail { throw ProjectError.writeFailed(URL(filePath: "/x"), reason: "잠깐 실패") }
      content.withLock { $0 = "옛 원고" }
    }
    try await Task.sleep(for: .milliseconds(50))
    let newer = try await queue.save(.project, change: 2) { content.withLock { $0 = "새 원고" } }

    #expect(newer == .written)
    #expect(try await old == .skippedStale)
    #expect(content.withLock { $0 } == "새 원고")
  }
}
