import AppKit
import UniformTypeIdentifiers

/// macOS 표준 저장·열기 창과 Finder 연동.
/// AppKit은 원래 편집기 파일에만 두지만, 이 창들은 SwiftUI에 대응하는 것이 없어 이 파일 한 곳에만 둔다.
enum SystemDialogs {
  /// 새 작품을 만들 위치와 이름을 묻는다. 처음에는 문서 폴더, 이후에는 마지막에 고른 폴더를 시스템이 기억한다.
  static func askNewProjectLocation() -> URL? {
    let panel = NSSavePanel()
    panel.title = "새 작품"
    panel.prompt = "만들기"
    panel.nameFieldLabel = "작품 이름:"
    panel.nameFieldStringValue = "새 작품"
    panel.allowedContentTypes = [.novelProject]
    panel.canCreateDirectories = true
    if !UserDefaults.standard.bool(forKey: "hasChosenProjectLocation") {
      panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    UserDefaults.standard.set(true, forKey: "hasChosenProjectLocation")
    return url
  }

  /// 이미 있는 작품(.novel)을 고른다.
  static func askExistingProject() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "작품 열기"
    panel.prompt = "열기"
    panel.allowedContentTypes = [.novelProject]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }

  static func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

extension SystemDialogs {
  /// 오류를 표준 경고 창으로 보여준다.
  static func showError(_ title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.runModal()
  }
}
