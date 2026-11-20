import AppKit
import NovelCore
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
  /// 창을 닫았는데 작품 폴더에 저장하지 못한 원고가 남았다. 다른 곳에 내보낼지 묻고, 내보냈으면 true.
  /// 안 고르면 원고는 앱을 끌 때까지 메모리에 남고, 끌 때 다시 묻는다.
  static func offerRescueOnClose(_ manuscripts: [(title: String, text: String)]) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "저장하지 못한 원고가 있어요"
    alert.informativeText = "작품 폴더에 쓸 수 없어 \(manuscripts.count)개 회차의 마지막 원고가 메모리에만 있어요. 다른 폴더에 .md 파일로 내보내 두세요. 앱을 끄면 사라져요."
    alert.addButton(withTitle: "다른 곳에 저장…")
    alert.addButton(withTitle: "나중에")
    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    return exportUnsaved(manuscripts)
  }

  /// 폴더를 골라 원고를 회차마다 .md로 내보낸다. 내보냈으면 true. 실패하면 이유를 보여 주고 false.
  static func exportUnsaved(_ manuscripts: [(title: String, text: String)]) -> Bool {
    let panel = NSOpenPanel()
    panel.title = "원고 내보내기"
    panel.message = "저장하지 못한 원고를 넣을 폴더를 고르세요. 같은 이름의 파일은 덮어쓰지 않아요."
    panel.prompt = "여기에 저장"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let folder = panel.url else { return false }
    do {
      let written = try RescueExport.write(manuscripts, to: folder)
      if let first = written.first { revealInFinder(first) }
      return true
    } catch {
      let reason = (error as? ProjectError)?.userMessage ?? error.localizedDescription
      showError("원고를 내보내지 못했어요", message: "\(reason) 다른 폴더를 골라 다시 시도해 주세요.")
      return false
    }
  }

  static func showError(_ title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.runModal()
  }
}
