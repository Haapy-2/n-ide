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
      try render(SettingsView(), name: "settings", size: CGSize(width: 460, height: 640), dark: dark)
      try render(ManuscriptEditor(content: Self.longText, style: Self.myungjoStyle), name: "editor-myungjo", size: CGSize(width: 1100, height: 760), dark: dark)
      try render(WorkspaceView(previewProject: ProjectFile(title: "회귀한 검성은 이번 생에서만큼은 조용히 살고 싶다")), name: "workspace-empty", size: CGSize(width: 1100, height: 760), dark: dark)
    }
  }

  /// 긴 본문: 대사와 서술이 섞인 문단을 여러 번 되풀이한다.
  private static let longText = ManuscriptEditor.Content(
    token: UUID(), episodeID: EpisodeID(rawValue: "snapshot"),
    text: String(repeating: """
      비가 그친 골목에는 아직 물 냄새가 남아 있었다. 그는 처마 끝에서 떨어지는 마지막 빗방울을 세다가, 문득 누군가의 발소리를 들었다.

      "여기서 뭐 해요?"

      돌아보니 우산도 없이 젖은 소녀가 서 있었다. 그는 대답 대신 검집을 고쳐 쥐었다. 오래된 습관이었다. 낯선 목소리 앞에서는 언제나 손이 먼저 움직였다.

      """, count: 6))

  /// 설정을 바꾼 편집 영역 예: 명조, 19pt, 줄 간격 2배, 본문 폭 34자.
  private static let myungjoStyle = EditorStyle(
    font: .appleMyungjo, fontSize: 19, lineSpacing: 2, paragraphSpacing: 0.8, lineWidthInCharacters: 34)

  private static let sampleRecent = [
    RecentProject(path: NSHomeDirectory() + "/Documents/달빛 아래 검.novel", title: "달빛 아래 검", episodeCount: 212, lastOpened: .now.addingTimeInterval(-86_400)),
    RecentProject(path: NSHomeDirectory() + "/Desktop/시험용 단편.novel", title: "시험용 단편", episodeCount: 3, lastOpened: .now.addingTimeInterval(-86_400 * 8)),
  ]

  /// 실제 창에 띄운 뒤 창 전체(툴바 포함)를 이미지로 뜬다.
  private func render(_ view: some View, name: String, size: CGSize, dark: Bool) throws {
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

    let file = "\(stage)-\(name)-\(dark ? "dark" : "light").png"
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
