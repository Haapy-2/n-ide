import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// Editor performance measurement (run by Scripts/perf.sh in a release build). Skipped in normal tests.
/// Results are printed as `NOVEL_PERF <name> <value,value,...>` lines that perf.sh turns into a table.
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

  /// Keystrokes: 1,000 in a 5,000-char episode. Each character is two compositions (setMarkedText) + one commit (insertText), like a Hangul IME.
  /// From receiving the event until the character is applied and layout and drawing finish.
  /// Character counting (text storage notification) and status bar fading, which run with every keystroke, are included too.
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

  /// Heaviest case with count refresh "live": copy the body and dispatch counting on every keystroke in a 100k-char episode.
  /// Only main-thread work is measured (input, body copy, starting the count task, layout/drawing). The counting itself runs elsewhere.
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

  /// Same-word multi-cursor: select 100 markers placed every 1,000 chars in a 100k-char episode with ⌘D, then 300 keystrokes.
  /// Each character is two compositions + one commit like `testKeystroke`. Spots must be spread across the body for the heaviest case of widely scattered edits.
  /// The target row stops at screen drawing (only the visible area is laid out immediately). Full-body layout is measured separately for reference: with 100 spots spread across the body
  /// everything is relaid out each time, but the app does that in the background in pieces, not during keystrokes.
  func testMultiCursorKeystroke100k() throws {
    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    let marker = "표시어"
    let base = String(repeating: try store.readEpisode(project.episodes[0].id), count: 20) as NSString
    var text = ""
    var start = 0
    for index in 0..<100 {
      let end = base.rangeOfComposedCharacterSequence(at: min(index * 1_000 + 500, base.length - 1)).location
      text += base.substring(with: NSRange(location: start, length: end - start)) + " \(marker) "
      start = end
    }
    text += base.substring(from: start)
    textView.replaceAllText(with: text)
    textView.setSelectedRange((text as NSString).range(of: marker))
    for _ in 1..<100 { textView.selectNextOccurrence(nil) }
    XCTAssertEqual(textView.multiCursorRanges?.count, 100, "표시어 100곳을 모두 골랐다")
    textView.scrollRangeToVisible(textView.selectedRange())
    settle()

    let clock = ContinuousClock()
    func type(_ count: Int, fullLayout: Bool) -> [Double] {
      (0..<count).map { index in
        milliseconds(clock.measure {
          switch index % 3 {
          case 0: textView.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
          case 1: textView.setMarkedText("가", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
          default: textView.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
          }
          if fullLayout { textView.layoutManager?.ensureLayout(for: textView.textContainer!) }
          textView.displayIfNeeded()
        })
      }
    }
    let samples = type(300, fullLayout: false)
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    let fullLayout = type(150, fullLayout: true)
    XCTAssertEqual(textView.multiCursorRanges?.count, 100, "내내 여러 커서였다")
    report("multi_cursor_100_keystroke_ms", samples)
    report("multi_cursor_100_keystroke_full_layout_ms", fullLayout)
  }

  /// Keystrokes with line numbers on: 300 near the end of a 100k-char episode (where computing the first visible paragraph's number counts the most).
  /// Each character is two compositions + one commit; every 30th is Return (line count changes, redrawing all visible numbers: the heaviest case).
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

  /// Episode switch: read a 5,000-char episode not yet opened this run, load it into the editor, and finish layout and drawing.
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

  /// Episode with pictures (PLAN ch.19 #6, decision 41): 5,000 chars + 10 image lines, measured against the same body without them in the same run.
  /// Keystrokes like `testKeystroke` with pictures on screen; switching in from another episode with the image cache empty
  /// (picture headers read, contents decode afterwards off the main thread, so not included).
  func testImageEpisode() throws {
    let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/tmp/perf-images-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let layout = ProjectLayout(root: folder.appending(path: "작품.novel"))
    try FileManager.default.createDirectory(at: layout.imagesFolder, withIntermediateDirectories: true)
    for index in 0..<10 {
      try writePerfImage(layout.imageFile(named: "\(index).png"), width: index.isMultiple(of: 2) ? 1600 : 3000, height: index.isMultiple(of: 2) ? 900 : 2000)
    }
    let plain = try store.readEpisode(project.episodes[0].id)
    let other = try store.readEpisode(project.episodes[1].id)
    var paragraphs = plain.components(separatedBy: "\n")
    let step = max(1, paragraphs.count / 10)
    for index in (0..<10).reversed() { paragraphs.insert(ImageLine.markdown(fileName: "\(index).png"), at: min(paragraphs.count, (index + 1) * step)) }
    let withImages = paragraphs.joined(separator: "\n")

    let (window, textView) = makeEditorWindow()
    defer { window.close() }
    textView.project = layout
    let clock = ContinuousClock()
    for (suffix, body) in [("", withImages), ("_plain", plain)] {
      textView.replaceAllText(with: body)
      let middle = (body as NSString).length / 2
      textView.setSelectedRange(NSRange(location: middle, length: 0))
      textView.scrollRangeToVisible(textView.selectedRange())
      settle()
      var samples: [Double] = []
      for index in 0..<1_000 {
        samples.append(milliseconds(clock.measure {
          switch index % 3 {
          case 0: textView.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
          case 1: textView.setMarkedText("가", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
          default: textView.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
          }
          textView.layoutManager?.ensureLayout(for: textView.textContainer!)
          textView.displayIfNeeded()
        }))
      }
      report("image_keystroke\(suffix)_ms", samples)

      var switches: [Double] = []
      for _ in 0..<7 {
        textView.replaceAllText(with: other)
        textView.displayIfNeeded()
        switches.append(milliseconds(clock.measure {
          textView.replaceAllText(with: body)
          textView.layoutManager?.ensureLayout(for: textView.textContainer!)
          textView.displayIfNeeded()
        }))
      }
      report("image_switch\(suffix)_ms", switches)
    }
  }

  private func writePerfImage(_ url: URL, width: Int, height: Int) throws {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: .systemTeal, ending: .systemIndigo)!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 45)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
  }

  /// Dragging a slider in Settings: style values change, new attributes are applied to the whole body, and the visible area redraws.
  /// Two sizes: 5,000 chars (normal episode) and 100k chars (very long episode). Font size alternates 17↔18.
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

  /// When the count changes while typing: with the whole workspace up (sidebar 500 episodes + editor),
  /// until the screen redraws after the current episode's single count changes. Happens every 0.2 s while typing.
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
        // SwiftUI updates the screen at the end of a run loop turn. Spin one turn and finish drawing.
        RunLoop.main.run(mode: .default, before: Date())
        window.displayIfNeeded()
        CATransaction.flush()
      }
      samples.append(milliseconds(elapsed))
    }
    report("sidebar_count_ms", samples)
  }

  // MARK: - Helpers

  /// Opening the snapshot panel: on an episode with 50 snapshots, open the panel, read the list/memos, until the diff with the latest finishes.
  /// Reading and diffing are off the main thread; whether the main thread blocks is covered by the keystroke measurement. This measures the user's wait.
  /// 5,000 chars (normal episode) and 100k chars (very long episode). The measurement project is built separately in build/tmp (so snapshots don't pile up in the dummy project).
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
      // Current text: a few paragraphs edited (the usual case when opening the panel).
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

  /// Restore from snapshot: replace a 100k-char body wholesale as one undo unit and redraw the visible area (main thread).
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

  /// Replace all: "그는" → "그녀석은" in a copy of the 500-episode dummy (open question 20, target 2 s). Per episode: pre-replace snapshot → body write →
  /// post-replace snapshot. Only execution after the confirmation is measured (counting happens before it). It's a copy, so other measurements' dummy is untouched.
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
    // Flush writes left by copying and earlier measurements to disk first. Otherwise the first F_FULLFSYNC would absorb them and inflate the replace.
    let barrier = try FileHandle(forUpdating: scratch.layout.projectFile)
    _ = fcntl(barrier.fileDescriptor, F_FULLFSYNC)
    try barrier.close()
    let start = ContinuousClock.now
    let report = await replace.confirm(pending)
    let elapsed = ContinuousClock.now - start
    XCTAssertEqual(report?.replaced.count, pending.plan.episodes.count)
    print("NOVEL_PERF replace_all_episodes \(pending.plan.episodes.count)")
    self.report("replace_all_500_ms", [milliseconds(elapsed)])

    // Opening the revert sheet (re-detecting by reading each episode's pre-replace snapshot and current text) and revert all.
    let detectStart = ContinuousClock.now
    let found = await replace.latestUndoable()
    let detected = ContinuousClock.now - detectStart
    let undoable = try XCTUnwrap(found)
    XCTAssertEqual(undoable.candidates.count, pending.plan.episodes.count)
    self.report("revert_detect_500_ms", [milliseconds(detected)])
    let revertStart = ContinuousClock.now
    let reverted = await replace.revert(undoable.record, Set(undoable.candidates.map(\.id)))
    let revertElapsed = ContinuousClock.now - revertStart
    XCTAssertEqual(reverted.episodes, pending.plan.episodes.count)
    self.report("revert_all_500_ms", [milliseconds(revertElapsed)])
  }

  /// Batch rename: rename every episode in a copy of the 500-episode dummy to `new name + number`. Measures until each episode's rename snapshot (file read →
  /// body/title/memo writes → prune) finishes, and the longest main-thread block meanwhile (how long the screen froze).
  func testBatchRename500() async throws {
    let copy = store.layout.root.deletingLastPathComponent().appending(path: "rename-\(UUID().uuidString).novel")
    try FileManager.default.copyItem(at: store.layout.root, to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    let scratch = ProjectStore(root: copy)
    let model = ProjectModel(project: try scratch.loadProject(), store: scratch, autosaveDelay: .seconds(60))
    let ids = Set(model.episodes.map(\.id))
    let gaps = MainThreadGaps()
    gaps.start()
    let start = ContinuousClock.now
    let outcome = await model.renameEpisodes(ids, by: .numbered(name: "회차", start: 1, numberFirst: false))
    let elapsed = ContinuousClock.now - start
    gaps.stop()
    XCTAssertEqual(outcome, .init(renamed: ids.count, unsnapshotted: 0))
    report("batch_rename_500_ms", [milliseconds(elapsed)])
    report("batch_rename_500_main_gap_ms", [milliseconds(gaps.longest)])
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

/// Wake on the main thread every 1 ms and record the longest gap between wakeups (the screen froze that long).
@MainActor
private final class MainThreadGaps {
  private(set) var longest: Duration = .zero
  private var ticker: Task<Void, Never>?

  func start() {
    ticker = Task { @MainActor in
      var last = ContinuousClock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(1))
        let now = ContinuousClock.now
        longest = max(longest, now - last)
        last = now
      }
    }
  }

  func stop() { ticker?.cancel() }
}
