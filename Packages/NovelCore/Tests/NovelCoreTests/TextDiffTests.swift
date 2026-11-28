import Foundation
import Testing
@testable import NovelCore

/// The diff engine. The diff view and restore decisions trust this result, so check line alignment and highlights precisely.
struct TextDiffTests {
  private func diff(_ old: String, _ new: String) throws -> TextDiff { try TextDiff(old: old, new: new) }

  // MARK: - Line level

  @Test func sameTextHasNoChanges() throws {
    let result = try diff("첫 줄\n둘째 줄", "첫 줄\n둘째 줄")
    #expect(result.rows == [.same(old: 0, new: 0), .same(old: 1, new: 1)])
    #expect(!result.hasChanges)
  }

  @Test func emptyTexts() throws {
    #expect(try diff("", "").rows.isEmpty)
    #expect(try diff("", "가\n나").rows == [.added(new: 0), .added(new: 1)], "빈 글에서 쓰면 모두 넣은 줄")
    #expect(try diff("가\n나", "").rows == [.removed(old: 0), .removed(old: 1)])
  }

  @Test func insertedLineKeepsOthersSideBySide() throws {
    let result = try diff("하나\n셋", "하나\n둘\n셋")
    #expect(result.rows == [.same(old: 0, new: 0), .added(new: 1), .same(old: 1, new: 2)])
  }

  @Test func removedLine() throws {
    let result = try diff("하나\n둘\n셋", "하나\n셋")
    #expect(result.rows == [.same(old: 0, new: 0), .removed(old: 1), .same(old: 2, new: 1)])
  }

  @Test func removeAndAddNextToEachOtherBecomeChangedPairs() throws {
    let result = try diff("앞\n지운 첫째\n지운 둘째\n뒤", "앞\n새 줄\n뒤")
    guard result.rows.count == 4, case .changed(0 + 1, 1, _) = result.rows[1] else {
      Issue.record("짝지은 줄이 같은 높이에 와야 한다: \(result.rows)")
      return
    }
    #expect(result.rows[2] == .removed(old: 2), "짝이 없는 줄은 지운 줄로 남는다")
    #expect(result.rows[3] == .same(old: 3, new: 2))
  }

  @Test func blankLinesAreLinesToo() throws {
    let result = try diff("가\n\n나", "가\n나")
    #expect(result.rows == [.same(old: 0, new: 0), .removed(old: 1), .same(old: 2, new: 1)])
  }

  @Test func nfdAndNfcAreTheSame() throws {
    let nfd = "한글 문장\n둘째".decomposedStringWithCanonicalMapping
    #expect(nfd.unicodeScalars.count != "한글 문장\n둘째".unicodeScalars.count)
    let result = try diff(nfd, "한글 문장\n둘째")
    #expect(!result.hasChanges, "다른 편집기가 자모로 풀어 저장해도 같은 글")
    #expect(result.oldLines[0].unicodeScalars.count == "한글 문장".unicodeScalars.count, "줄은 NFC로 맞춰 둔다")
  }

  // MARK: - Within modified lines

  private func highlight(_ old: String, _ new: String) throws -> TextDiff.Highlight? {
    let result = try diff(old, new)
    guard result.rows.count == 1, case .changed(0, 0, let highlight) = result.rows[0] else { return nil }
    return highlight
  }

  @Test func singleCharacterInWord() throws {
    // 나는 밥을 먹었다: only "을" (4)
    #expect(try highlight("나는 밥을 먹었다", "나는 밥를 먹었다") == .ranges(old: [4..<5], new: [4..<5]))
  }

  @Test func insertedCharactersInWordOnlyOnNewSide() throws {
    // 그는 했다 → 그는 했었다: nothing to highlight in the past column, only "었" (4) in the present column
    #expect(try highlight("그는 그 일을 했다", "그는 그 일을 했었다") == .ranges(old: [], new: [9..<10]))
  }

  @Test func wholeWordWhenNothingInCommon() throws {
    #expect(try highlight("그는 빨리 달렸다", "그는 천천히 달렸다") == .ranges(old: [3..<5], new: [3..<6]))
  }

  @Test func insertedWordDoesNotPaintSpaces() throws {
    // 그는 달렸다 → 그는 아주 빨리 달렸다: only the two words "아주 빨리"; the space between isn't highlighted
    #expect(try highlight("그는 숲길을 달렸다", "그는 숲길을 아주 빨리 달렸다") == .ranges(old: [], new: [7..<9, 10..<12]))
  }

  @Test func mostlyChangedLineIsWholeLine() throws {
    #expect(try highlight("오늘은 비가 왔다", "내일 아침에는 눈이 내릴 것이다") == .wholeLine)
  }

  /// Default threshold (PLAN ch.10 #4): lengthening a short line highlights only the added part; rewriting a whole sentence highlights the whole line.
  @Test func defaultRatioKeepsShortDialogueEditsVisible() throws {
    guard case .ranges = try highlight("\"어디 가?\"", "\"어디 가는 거야?\"") else {
      Issue.record("짧은 대사를 늘린 것은 늘어난 곳만 칠해야 한다")
      return
    }
    #expect(try highlight("그는 검을 들었다.", "칼날이 달빛에 번뜩였다.") == .wholeLine)
  }

  @Test func ratioIsAdjustable() throws {
    let result = try TextDiff(old: "그는 빨리 달렸다", new: "그는 천천히 달렸다", wholeLineRatio: 0.2)
    #expect(result.rows == [.changed(old: 0, new: 0, .wholeLine)], "기준을 낮추면 같은 변화도 줄 전체")
  }

  @Test func emojiIsOneCharacter() throws {
    #expect(try highlight("정말 좋아 😀", "정말 좋아 😂") == .ranges(old: [6..<7], new: [6..<7]))
    #expect(try highlight("가족 👨‍👩‍👧 사진", "가족 👨‍👩‍👦 사진") == .ranges(old: [3..<4], new: [3..<4]), "합쳐진 이모지도 한 글자")
  }

  // MARK: - Large texts and cancellation

  @Test func overLimitIsLineOnly() throws {
    let result = try TextDiff(old: "나는 밥을 먹었다", new: "나는 밥를 먹었다", inlineLimit: 0)
    #expect(result.isLineOnly)
    #expect(result.rows == [.changed(old: 0, new: 0, .wholeLine)])
  }

  @Test func cancelledTaskThrows() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try TextDiff(old: "가", new: "나")
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
  }

  @Test func rowsCoverEveryLineOnce() throws {
    let old = (0..<200).map { "문단 \($0) 내용" }.joined(separator: "\n")
    var newLines = (0..<200).map { "문단 \($0) 내용" }
    newLines.remove(at: 50)
    newLines.insert("새 문단", at: 120)
    newLines[150] = "문단 150 고친 내용"
    let result = try diff(old, newLines.joined(separator: "\n"))
    var olds: [Int] = []
    var news: [Int] = []
    for row in result.rows {
      switch row {
      case .same(let o, let n), .changed(let o, let n, _): olds.append(o); news.append(n)
      case .removed(let o): olds.append(o)
      case .added(let n): news.append(n)
      }
    }
    #expect(olds == Array(0..<200), "과거 줄이 빠짐없이 순서대로")
    #expect(news == Array(0..<200), "현재 줄이 빠짐없이 순서대로")
  }

  /// Whatever text arrives, it never hangs or crashes, and every line appears exactly once.
  @Test func oddInputsNeverCrash() throws {
    let samples = [
      "", "\n", "\n\n\n", "가", " ", "  가  나  ", "\r\n가\r\n", "😀\n👨‍👩‍👧\n",
      String(repeating: "같은 줄\n", count: 50), String(repeating: "가 ", count: 300),
      "한글".decomposedStringWithCanonicalMapping, "\u{200B}보이지 않는 글자",
    ]
    for old in samples {
      for new in samples {
        let result = try TextDiff(old: old, new: new)
        var olds = 0
        var news = 0
        for row in result.rows {
          switch row {
          case .same, .changed: olds += 1; news += 1
          case .removed: olds += 1
          case .added: news += 1
          }
        }
        #expect(olds == result.oldLines.count && news == result.newLines.count, "\(old.debugDescription) → \(new.debugDescription)")
      }
    }
  }
}
