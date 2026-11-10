import AppKit
import SwiftUI
import XCTest
@testable import NovelEditor

/// 화면을 라이트/다크로 그려 docs/design-snapshots/에 PNG로 저장한다.
/// 평소 테스트에서는 건너뛰고, Scripts/snapshots.sh로 실행할 때만 만든다.
@MainActor
final class DesignSnapshotTests: XCTestCase {
  private let stage = "01"

  func testRenderSnapshots() throws {
    guard ProcessInfo.processInfo.environment["NOVEL_SNAPSHOTS"] == "1" else {
      throw XCTSkip("Scripts/snapshots.sh로 실행할 때만 스냅샷을 만든다")
    }
    for dark in [false, true] {
      try render(ProjectPickerView(), name: "picker-empty", size: CGSize(width: 560, height: 420), dark: dark)
      try render(WorkspaceView(projectTitle: "회귀한 검성은 이번 생에서만큼은 조용히 살고 싶다"), name: "workspace-empty", size: CGSize(width: 1100, height: 760), dark: dark)
    }
  }

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
