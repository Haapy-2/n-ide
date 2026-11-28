import AppKit
import NovelCore
import UniformTypeIdentifiers

/// macOS standard save/open panels and Finder integration.
/// AppKit normally lives only in editor files, but these panels have no SwiftUI equivalent, so they live in this one file.
enum SystemDialogs {
  /// Ask where and under what name to create a new project. Starts at Documents; afterwards the system remembers the last chosen folder.
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

  /// Picture files to put into the manuscript. Empty if cancelled.
  static func askImages(multiple: Bool) -> [URL] {
    let panel = NSOpenPanel()
    panel.title = multiple ? "그림 넣기" : "다른 그림으로 바꾸기"
    panel.prompt = multiple ? "넣기" : "바꾸기"
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = multiple
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK else { return [] }
    return panel.urls
  }

  static func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

extension SystemDialogs {
  /// The window closed with manuscripts that couldn't be saved to the project folder. Ask whether to export elsewhere; true if exported.
  /// If nothing is chosen, the manuscripts stay in memory until quit, and quit asks again.
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

  /// The window closed and the episode list (project.json) ultimately couldn't be written (same question as at quit). True if retry is chosen.
  /// The window is already closed, so there's no cancel.
  static func retryProjectSaveOnClose() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "회차 목록을 저장하지 못했어요"
    alert.informativeText = "이대로 닫으면 회차 추가·순서·이름을 바꾼 것이 사라질 수 있어요. 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 시도해 주세요."
    alert.addButton(withTitle: "다시 시도")
    alert.addButton(withTitle: "그래도 닫기")
    return alert.runModal() == .alertFirstButtonReturn
  }

  enum SlowSaveChoice {
    case finished, export, cancel
  }

  /// Saving is slow during quit. Closes by itself when saving (`finishing`) finishes, returning `.finished`.
  /// `runModal` isn't used: while a modal is up, main-actor work stops, so neither save retries nor auto-closing ran.
  /// So the alert is shown like a normal window and button presses are handled directly.
  static func waitForSaves(until finishing: Task<Void, Never>) async -> SlowSaveChoice {
    let alert = NSAlert()
    alert.messageText = "저장을 마치는 중이에요"
    alert.informativeText = "작품 폴더에 쓰는 데 평소보다 오래 걸리고 있어요. 네트워크 드라이브나 iCloud라면 연결을 확인해 주세요. 저장이 끝나면 저절로 꺼져요."
    alert.addButton(withTitle: "기다리지 않고 내보내기…")
    alert.addButton(withTitle: "종료 취소")
    let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.startAnimation(nil)
    alert.accessoryView = spinner
    alert.layout()
    let window = alert.window
    return await withCheckedContinuation { continuation in
      let choice = SlowSaveAnswer(continuation, window: window)
      for (index, button) in alert.buttons.enumerated() {
        button.tag = index
        button.target = choice
        button.action = #selector(SlowSaveAnswer.pressed(_:))
      }
      window.level = .modalPanel
      window.center()
      window.makeKeyAndOrderFront(nil)
      Task { @MainActor in
        await finishing.value
        choice.answer(.finished)
      }
    }
  }

  enum BackupChoice {
    case restore, export, discard
  }

  /// On opening a project, manuscripts that couldn't be written to the project folder last time remain in the out-of-project backup.
  static func offerBackupRestore(episodeNames: [String]) -> BackupChoice {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "저장하지 못한 원고가 있어요"
    let list = episodeNames.prefix(5).joined(separator: ", ") + (episodeNames.count > 5 ? " 외 \(episodeNames.count - 5)개" : "")
    alert.informativeText = "지난번에 작품 폴더에 쓰지 못한 원고가 남아 있어요: \(list).\n되살리면 지금 파일의 글은 스냅샷 ‘복원 전’으로 남겨 두어 비교하거나 되돌릴 수 있어요."
    alert.addButton(withTitle: "되살리기")
    alert.addButton(withTitle: "다른 곳에 내보내기…")
    alert.addButton(withTitle: "휴지통으로 버리기")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return .restore
    case .alertSecondButtonReturn: return .export
    default: return .discard
    }
  }

  /// Pick a folder and export manuscripts as one .md per episode. True if exported. On failure show why and return false.
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

/// Answer to the slow-save alert. Take only whichever comes first, a button or save completion, and close the window.
@MainActor
private final class SlowSaveAnswer: NSObject {
  private var continuation: CheckedContinuation<SystemDialogs.SlowSaveChoice, Never>?
  private let window: NSWindow

  init(_ continuation: CheckedContinuation<SystemDialogs.SlowSaveChoice, Never>, window: NSWindow) {
    self.continuation = continuation
    self.window = window
  }

  @objc func pressed(_ sender: NSButton) {
    answer(sender.tag == 0 ? .export : .cancel)
  }

  func answer(_ choice: SystemDialogs.SlowSaveChoice) {
    guard let continuation else { return }
    self.continuation = nil
    window.orderOut(nil)
    continuation.resume(returning: choice)
  }
}
