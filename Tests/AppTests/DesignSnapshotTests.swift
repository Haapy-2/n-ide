import AppKit
import NovelCore
import SwiftUI
import XCTest
@testable import NovelEditor

/// 화면을 라이트/다크로 그려 docs/design-snapshots/에 PNG로 저장한다.
/// 평소 테스트에서는 건너뛰고, Scripts/snapshots.sh로 실행할 때만 만든다.
@MainActor
final class DesignSnapshotTests: XCTestCase {
  private let stage = "10"

  func testRenderSnapshots() throws {
    guard ProcessInfo.processInfo.environment["NOVEL_SNAPSHOTS"] == "1" else {
      throw XCTSkip("Scripts/snapshots.sh로 실행할 때만 스냅샷을 만든다")
    }
    for dark in [false, true] {
      try render(ProjectPickerView(recent: []), name: "picker-empty", size: CGSize(width: 560, height: 420), dark: dark)
      try render(ProjectPickerView(recent: Self.sampleRecent), name: "picker-recent", size: CGSize(width: 560, height: 420), dark: dark)
      try render(ManuscriptEditor(content: Self.longText), name: "editor-long-text", size: CGSize(width: 1100, height: 760), dark: dark)
      for section in SettingsSection.allCases {
        try render(SettingsView(section: section), name: "settings-\(section.rawValue)", size: SettingsView.windowSize, dark: dark)
      }
      try render(Self.progressStyles, name: "progress-styles", size: CGSize(width: 560, height: 200), dark: dark)
      try render(ManuscriptEditor(content: Self.longText, style: Self.myungjoStyle), name: "editor-myungjo", size: CGSize(width: 1100, height: 760), dark: dark)
      try render(WorkspaceView(previewProject: ProjectFile(title: "회귀한 검성은 이번 생에서만큼은 조용히 살고 싶다")), name: "workspace-empty", size: CGSize(width: 1100, height: 760), dark: dark)
    }
  }

  /// 편집기 줄 번호(왼쪽 여백 끝에서 20pt). 긴 문단은 첫 줄에만 번호가 붙는다.
  func testRenderLineNumbers() throws {
    guard ProcessInfo.processInfo.environment["NOVEL_SNAPSHOTS"] == "1" else {
      throw XCTSkip("Scripts/snapshots.sh로 실행할 때만 스냅샷을 만든다")
    }
    for dark in [false, true] {
      try render(
        ManuscriptEditor(content: Self.longText, showsLineNumbers: true), name: "editor-line-numbers",
        size: CGSize(width: 1100, height: 760), dark: dark, stage: "11")
    }
  }

  /// 토스트 두 가지(문구만, 글자 버튼 있음). 유리 바탕은 화면 밖 그리기에서 하얗게 찍히므로 실제 앱에서도 본다.
  func testRenderToasts() throws {
    guard ProcessInfo.processInfo.environment["NOVEL_SNAPSHOTS"] == "1" else {
      throw XCTSkip("Scripts/snapshots.sh로 실행할 때만 스냅샷을 만든다")
    }
    let view = VStack(alignment: .trailing, spacing: 12) {
      ToastView(toast: Toast(message: "저장했어요"))
      ToastView(toast: Toast(message: "스냅샷을 찍었어요", action: .init(title: "메모 달기") {}))
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .background(Color.paper)
    for dark in [false, true] {
      try render(view, name: "toast", size: CGSize(width: 420, height: 140), dark: dark, stage: "12")
    }
  }

  /// 스냅샷 판: 과거 원고와 고친 지금 원고를 실제처럼 비교해 띄운다.
  func testRenderSnapshotPanel() async throws {
    guard ProcessInfo.processInfo.environment["NOVEL_SNAPSHOTS"] == "1" else {
      throw XCTSkip("Scripts/snapshots.sh로 실행할 때만 스냅샷을 만든다")
    }
    let folder = snapshotsFolder.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("build/tmp/\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = try ProjectStore.create(at: folder.appendingPathComponent("작품.novel"), title: "x")
    let episode = EpisodeID.make()
    let now = Date()
    try store.writeSnapshot(Self.panelPast, episode: episode, kind: .leave, at: now.addingTimeInterval(-86_400))
    try store.writeSnapshot(Self.panelPast, episode: episode, kind: .manual, memo: "골목 장면 고치기 전", at: now.addingTimeInterval(-3_600))
    try store.writeSnapshot(Self.panelPast + "\n", episode: episode, kind: .auto, at: now.addingTimeInterval(-600))
    let browser = SnapshotBrowser(store: store, episodeID: episode, currentText: Self.panelCurrent)
    await browser.load()
    browser.select(browser.items![1].id)
    for _ in 0..<100 {
      if case .ready = browser.comparison { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    for dark in [false, true] {
      let view = Color.paper.overlay {
        SnapshotPanel(browser: browser, title: "스냅샷 · 3화 비 오는 날", onClose: {})
      }
      try render(view, name: "snapshot-panel", size: CGSize(width: 1100, height: 760), dark: dark, stage: "11")
    }
  }

  private static let panelPast = """
    비가 그친 골목에는 아직 물 냄새가 남아 있었다.
    그는 처마 끝에서 떨어지는 마지막 빗방울을 세다가, 문득 누군가의 발소리를 들었다.

    "여기서 뭐 해요?"

    돌아보니 우산도 없이 젖은 소녀가 서 있었다.
    그는 대답 대신 검집을 고쳐 쥐었다. 오래된 습관이었다.
    낯선 목소리 앞에서는 언제나 손이 먼저 움직였다.
    소녀는 한 걸음 물러섰다.
    "무서운 사람은 아니에요."
    그는 그렇게 말했지만, 손은 여전히 검집 위에 있었다.
    골목 끝에서 개 짖는 소리가 났다.
    둘은 동시에 그쪽을 보았다.
    """

  private static let panelCurrent = """
    비가 그친 골목에는 아직 물 냄새가 남아 있었다.
    그는 처마 끝에서 떨어지는 마지막 빗방울을 세다가, 문득 낯선 발소리를 들었다.

    "여기서 뭐 하세요?"

    돌아보니 우산도 없이 젖은 소녀가 서 있었다.
    그는 대답 대신 검집을 고쳐 쥐었다. 오래된 습관이었다.
    낯선 목소리 앞에서는 언제나 손이 먼저 움직였다.
    소녀는 한 걸음 물러섰다.
    "무서운 사람은 아니에요."
    그는 그렇게 말했지만, 손은 여전히 검집 위에 있었다.
    멀리서 종소리가 울렸다. 저녁 예배를 알리는 소리였다.
    둘은 동시에 그쪽을 보았다.
    소녀가 먼저 웃었다.
    """

  private static let longText = ManuscriptEditor.Content(
    token: UUID(), episodeID: EpisodeID(rawValue: "snapshot"),
    text: String(repeating: """
      비가 그친 골목에는 아직 물 냄새가 남아 있었다. 그는 처마 끝에서 떨어지는 마지막 빗방울을 세다가, 문득 누군가의 발소리를 들었다.

      "여기서 뭐 해요?"

      돌아보니 우산도 없이 젖은 소녀가 서 있었다. 그는 대답 대신 검집을 고쳐 쥐었다. 오래된 습관이었다. 낯선 목소리 앞에서는 언제나 손이 먼저 움직였다.

      """, count: 6))

  private static let myungjoStyle = EditorStyle(
    font: .appleMyungjo, fontSize: 19, lineSpacing: 2, paragraphSpacing: 0.8, lineWidthInCharacters: 34)

  /// 진행률 모양 세 가지(고리, 꽉 찬 원, 막대) × 97%·48%·112%.
  private static var progressStyles: some View {
    VStack(alignment: .trailing, spacing: 10) {
      ForEach(GoalProgressStyle.allCases, id: \.self) { style in
        HStack(spacing: 24) {
          ForEach([4_850, 2_400, 5_600], id: \.self) { value in
            GoalProgress(value: value, goal: 5_000, style: style)
          }
        }
      }
    }
    .font(.system(size: 11).monospacedDigit())
    .foregroundStyle(Color.inkMuted)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.paper)
  }

  private static let sampleRecent = [
    RecentProject(path: NSHomeDirectory() + "/Documents/달빛 아래 검.novel", title: "달빛 아래 검", episodeCount: 212, lastOpened: .now.addingTimeInterval(-86_400)),
    RecentProject(path: NSHomeDirectory() + "/Desktop/시험용 단편.novel", title: "시험용 단편", episodeCount: 3, lastOpened: .now.addingTimeInterval(-86_400 * 8)),
  ]

  /// 실제 창에 띄운 뒤 창 전체(툴바 포함)를 이미지로 뜬다.
  private func render(_ view: some View, name: String, size: CGSize, dark: Bool, stage: String? = nil) throws {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false  // ARC가 관리하므로 닫을 때 한 번 더 해제되지 않게
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = NSHostingView(rootView: view)
    window.setContentSize(size)
    window.orderFront(nil)
    defer { window.close() }
    // SwiftUI가 레이아웃과 그리기를 마치도록 잠깐 돌린다.
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))

    let frameView = try XCTUnwrap(window.contentView?.superview)
    let rep = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
    frameView.cacheDisplay(in: frameView.bounds, to: rep)
    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

    let file = "\(stage ?? self.stage)-\(name)-\(dark ? "dark" : "light").png"
    try png.write(to: snapshotsFolder.appendingPathComponent(file))
  }

  private var snapshotsFolder: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // AppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // 저장소 루트
      .appendingPathComponent("docs/design-snapshots")
  }
}
