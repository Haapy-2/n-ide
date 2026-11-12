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
