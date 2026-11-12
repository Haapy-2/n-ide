import AppKit
import NovelCore
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
  /// 키 입력마다 함께 불리는 글자 수 세기(텍스트 저장소 알림)와 상태 줄 흐려짐도 붙여서 잰다(9단계).
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

  // MARK: - 도구

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
