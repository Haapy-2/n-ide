import Foundation
import Synchronization
import Testing
@testable import NovelCore

/// 저장 줄. "늦게 끝난 옛 저장이 최신 원고를 되돌리는 일"이 없어야 한다 (SPEC 6장).
struct SaveQueueTests {
  private let fast: [Duration] = [.milliseconds(5), .milliseconds(5), .milliseconds(5)]

  /// 옛 저장(변경 1)이 새 저장(변경 2)보다 늦게 도착하는 경우를 그대로 재현한다.
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

  @Test func sameChangeNumberIsNotWrittenTwice() async throws {
    let queue = SaveQueue(retryDelays: fast)
    let id = EpisodeID.make()
    #expect(try await queue.save(.episode(id), change: 3) {} == .written)
    #expect(try await queue.save(.episode(id), change: 3) {} == .skippedStale)
  }

  /// 저장 100개를 뒤죽박죽 순서로 동시에 보내도 마지막에는 가장 높은 번호의 내용이 남는다.
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
    // 다른 회차는 번호가 따로 간다.
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

  /// 다시 시도하기 전마다 알려 준다(상태 줄 "다시 시도 중"). 처음부터 성공하면 부르지 않는다.
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
    // 처음 1번 + 재시도 3번
    #expect(attempts.withLock { $0 } == 4)
    #expect(await queue.lastWrittenChange(for: .project) == nil)
  }

  /// 옛 저장이 실패해서 재시도를 기다리는 사이에 새 저장이 끝나면, 옛 저장은 다시 쓰지 않고 포기한다.
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
