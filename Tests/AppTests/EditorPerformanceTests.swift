import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// 편집기 성능 측정 (Scripts/perf.sh가 릴리스 빌드로 실행). 평소 테스트에서는 건너뛴다.
/// 결과는 `NOVEL_PERF <이름> <값,값,...>` 줄로 출력하고 perf.sh가 표로 만든다.
@MainActor
final class EditorPerformanceTests: XCTestCase {
  private var store: ProjectStore!
  private var project: ProjectFile!

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["NOVEL_PERF_PROJECT"] else {
      throw XCTSkip("Scripts/perf.sh로 실행할 때만 잰다")
    }
    store = ProjectStore(root: URL(filePath: path, directoryHint: .isDirectory))
    project = try store.loadProject()
  }

  /// 키 입력: 5,000자 회차에서 1,000번. 한글 IME처럼 조합(setMarkedText) 두 번 + 확정(insertText) 한 번을 한 글자로.
  /// 이벤트를 받은 때부터 글자가 반영되고 레이아웃과 그리기가 끝날 때까지.
  /// 키 입력마다 함께 불리는 글자 수 세기(텍스트 저장소 알림)와 상태 줄 흐려짐도 붙여서 잰다.
  func testKeystroke() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    let counter = CharacterCounter()
    counter.attach(textView)
    let fade = StatusBarFade()
    let text = try store.readEpisode(project.episodes[0].id)
    counter.begin(episode: project.episodes[0].id, text: text, known: nil)
    textView.replaceAllText(with: text)
    textView.setSelectedRange(NSRange(location: 2_500, length: 0))
    settle()

    var samples: [Double] = []
    let clock = ContinuousClock()
    for index in 0..<1_000 {
      let elapsed = clock.measure {
        switch index % 3 {
        case 0: textView.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        case 1: textView.setMarkedText("가", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        default: textView.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        fade.noteInput()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.displayIfNeeded()
      }
      samples.append(milliseconds(elapsed))
    }
    report("keystroke_ms", samples)
  }

  /// 글자 수 갱신을 "실시간"으로 했을 때 가장 무거운 경우: 10만 자 회차에서 키 입력마다 본문을 복사해 세기를 맡긴다.
  /// 메인 스레드에서 하는 일(입력, 본문 복사, 세기 작업 시작, 레이아웃·그리기)만 잰다. 세기 자체는 밖에서 돈다.
  func testKeystrokeRealtimeCount100k() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    let counter = CharacterCounter(interval: .zero)
    counter.attach(textView)
    let text = String(repeating: try store.readEpisode(project.episodes[0].id), count: 20)
    counter.begin(episode: project.episodes[0].id, text: text, known: nil)
    textView.replaceAllText(with: text)
    textView.setSelectedRange(NSRange(location: 50_000, length: 0))
    settle()

    var samples: [Double] = []
    let clock = ContinuousClock()
    for _ in 0..<300 {
      let elapsed = clock.measure {
        textView.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
        counter.recountNow()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.displayIfNeeded()
      }
      samples.append(milliseconds(elapsed))
    }
    report("keystroke_realtime_100k_ms", samples)
  }

  /// 줄 번호를 켠 키 입력: 10만 자 회차 거의 끝(보이는 첫 문단 번호를 구하려고 앞을 가장 많이 셈)에서 300번.
  /// 조합 두 번 + 확정 한 번을 한 글자로, 30번에 한 번은 엔터(줄 수가 바뀌어 보이는 번호를 모두 다시 그리는 가장 무거운 경우).
  func testKeystrokeLineNumbers100k() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    textView.showsLineNumbers = true
    let text = String(repeating: try store.readEpisode(project.episodes[0].id), count: 20)
    textView.replaceAllText(with: text)
    let end = (text as NSString).length - 200
    textView.setSelectedRange(NSRange(location: end, length: 0))
    textView.scrollRangeToVisible(textView.selectedRange())
    settle()

    var samples: [Double] = []
    let clock = ContinuousClock()
    for index in 0..<300 {
      let elapsed = clock.measure {
        if index % 30 == 29 {
          textView.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
          switch index % 3 {
          case 0: textView.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
          case 1: textView.setMarkedText("가", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
          default: textView.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
          }
        }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.displayIfNeeded()
      }
      samples.append(milliseconds(elapsed))
    }
    report("keystroke_line_numbers_100k_ms", samples)
  }

  /// 회차 전환: 이번 실행에서 처음 여는 5,000자 회차를 읽어 편집기에 올리고 레이아웃·그리기를 마칠 때까지.
  func testEpisodeSwitch() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    var samples: [Double] = []
    let clock = ContinuousClock()
    for episode in project.episodes[1..<8] {
      let elapsed = try clock.measure {
        textView.replaceAllText(with: try store.readEpisode(episode.id))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.displayIfNeeded()
      }
      samples.append(milliseconds(elapsed))
    }
    report("switch_ms", samples)
  }

  /// 설정 창에서 슬라이더를 끌 때: 모양 값이 바뀌어 본문 전체에 새 속성을 입히고 보이는 곳을 다시 그리기까지.
  /// 5,000자(보통 회차)와 10만 자(아주 긴 회차) 두 가지. 글자 크기를 17↔18로 번갈아 바꾼다.
  func testStyleChange() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    let text = try store.readEpisode(project.episodes[0].id)
    for (name, body) in [("style_5k_ms", text), ("style_100k_ms", String(repeating: text, count: 20))] {
      textView.replaceAllText(with: body)
      textView.displayIfNeeded()
      settle()
      var samples: [Double] = []
      let clock = ContinuousClock()
      for index in 0..<20 {
        let style = EditorStyle(font: .pretendard, fontSize: index % 2 == 0 ? 18 : 17, lineSpacing: 1.75, paragraphSpacing: 0.6, lineWidthInCharacters: 40)
        let elapsed = clock.measure {
          textView.style = style
          textView.displayIfNeeded()
        }
        samples.append(milliseconds(elapsed))
      }
      report(name, samples)
    }
  }

  /// 타이핑 중 글자 수가 바뀔 때: 작업 공간 전체(사이드바 500회차 + 편집기)가 떠 있는 채로
  /// 지금 회차의 글자 수 하나가 바뀌어 화면이 다시 그려질 때까지. 치는 동안 0.2초마다 한 번 일어난다.
  func testSidebarCountUpdate() throws {
    let model = ProjectModel(project: project, store: store)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: WorkspaceView(model: model))
    window.orderFront(nil)
    defer { window.close() }
    settle()
    settle()

    let id = project.episodes[0].id
    var samples: [Double] = []
    let clock = ContinuousClock()
    for index in 0..<60 {
      let elapsed = clock.measure {
        model.recordCount(CharacterCount(withSpaces: 5_000 + index, withoutSpaces: 4_000 + index), for: id)
        // SwiftUI는 런루프 한 바퀴 끝에 화면을 갱신한다. 한 바퀴 돌리고 그리기까지 마친다.
        RunLoop.main.run(mode: .default, before: Date())
        window.displayIfNeeded()
        CATransaction.flush()
      }
      samples.append(milliseconds(elapsed))
    }
    report("sidebar_count_ms", samples)
  }

  // MARK: - 도구

  /// 스냅샷 판 열기: 스냅샷 50개 찬 회차에서 판을 열어 목록·메모를 읽고, 가장 최근 것과 비교가 끝날 때까지.
  /// 읽기와 비교는 메인 스레드 밖이라, 메인 스레드가 막히는지는 키 입력 측정이 따로 본다. 여기서는 사용자가 기다리는 시간.
  /// 5,000자(보통 회차)와 10만 자(아주 긴 회차). 측정용 작품은 build/tmp에 따로 만든다(더미 작품에 스냅샷을 쌓지 않게).
  func testSnapshotPanelOpen() async throws {
    let text = try store.readEpisode(project.episodes[0].id)
    let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/tmp/perf-snapshots-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let scratch = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "측정")
    for (name, body) in [("panel_open_5k_ms", text), ("panel_open_100k_ms", String(repeating: text, count: 20))] {
      let id = EpisodeID.make()
      let start = Date(timeIntervalSince1970: 1_800_000_000)
      for index in 0..<50 {
        _ = try scratch.writeSnapshot(body + "\(index)", episode: id, kind: .auto, memo: "메모 \(index)", at: start.addingTimeInterval(Double(index)))
      }
      // 지금 글: 문단 몇 개를 고친 것(판을 여는 보통 경우).
      let current = body.replacingOccurrences(of: "\n\n", with: "\n\n고친 문장. ", options: [], range: body.startIndex..<body.index(body.startIndex, offsetBy: body.count / 3))
      var samples: [Double] = []
      let clock = ContinuousClock()
      for _ in 0..<10 {
        let elapsed = try await clock.measure {
          let browser = SnapshotBrowser(store: scratch, episodeID: id, currentText: current)
          await browser.load()
          while case .comparing = browser.comparison { try await Task.sleep(for: .microseconds(200)) }
          guard case .ready = browser.comparison else { throw XCTSkip("비교 실패") }
        }
        samples.append(milliseconds(elapsed))
      }
      report(name, samples)
    }
  }

  /// 스냅샷으로 되돌리기: 10만 자 본문을 실행 취소 한 단위로 통째 바꾸고 보이는 곳을 다시 그리기까지(메인 스레드).
  func testRestoreReplace100k() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    let text = String(repeating: try store.readEpisode(project.episodes[0].id), count: 20)
    let other = text.replacingOccurrences(of: "다.", with: "었다.")
    textView.replaceAllText(with: text)
    textView.displayIfNeeded()
    settle()
    var samples: [Double] = []
    let clock = ContinuousClock()
    for index in 0..<20 {
      let elapsed = clock.measure {
        _ = textView.replaceAllUndoably(with: index % 2 == 0 ? other : text, actionName: "측정")
        textView.displayIfNeeded()
      }
      samples.append(milliseconds(elapsed))
    }
    report("restore_100k_ms", samples)
  }

  /// 전체 바꾸기: 더미 500화의 사본에서 "그는" → "그녀석은"(미결정 20, 목표 2초). 회차마다 바꾸기 전 스냅샷 → 본문 쓰기 →
  /// 바꾼 뒤 스냅샷. 확인 창 뒤 실행만 잰다(세기는 확인 창 전). 사본이라 다른 측정의 더미는 그대로다.
  func testReplaceAll500() async throws {
    let copy = store.layout.root.deletingLastPathComponent().appending(path: "replace-\(UUID().uuidString).novel")
    try FileManager.default.copyItem(at: store.layout.root, to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    let scratch = ProjectStore(root: copy)
    let model = ProjectModel(project: try scratch.loadProject(), store: scratch, autosaveDelay: .seconds(60))
    let replace = ProjectReplace(
      store: scratch, autosaver: model.autosaver, episodeIDs: { model.episodes.map(\.id) },
      recordCount: { model.recordCount($0, for: $1) })
    replace.replacement = "그녀석은"
    await replace.prepare(query: "그는", caseSensitive: false)
    let pending = try XCTUnwrap(replace.pending)
    // 사본 만들기와 앞선 측정이 남긴 쓰기를 먼저 디스크에 내린다. 안 그러면 첫 F_FULLFSYNC가 그것까지 떠안아 바꾸기에 얹힌다.
    let barrier = try FileHandle(forUpdating: scratch.layout.projectFile)
    _ = fcntl(barrier.fileDescriptor, F_FULLFSYNC)
    try barrier.close()
    let start = ContinuousClock.now
    let report = await replace.confirm(pending)
    let elapsed = ContinuousClock.now - start
    XCTAssertEqual(report?.replaced.count, pending.plan.episodes.count)
    print("NOVEL_PERF replace_all_episodes \(pending.plan.episodes.count)")
    self.report("replace_all_500_ms", [milliseconds(elapsed)])
  }

  private func makeEditorWindow() -> (NSWindow, ManuscriptTextView) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let scrollView = NSScrollView(frame: window.contentLayoutRect)
    let textView = ManuscriptTextView.make()
    textView.frame = scrollView.bounds
    scrollView.documentView = textView
    window.contentView = scrollView
    window.orderFront(nil)
    window.makeFirstResponder(textView)
    return (window, textView)
  }

  private func settle() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  }

  private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
  }

  private func report(_ name: String, _ values: [Double]) {
    print("NOVEL_PERF \(name) " + values.map { String(format: "%.3f", $0) }.joined(separator: ","))
  }
}
