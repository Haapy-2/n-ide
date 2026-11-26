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

  /// 창을 닫았는데 회차 목록(project.json)을 끝내 쓰지 못했을 때(종료 때와 같은 물음). 다시 시도를 고르면 true.
  /// 창은 이미 닫혀 취소는 없다.
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

  /// 종료하는데 저장이 늦을 때. 저장(`finishing`)이 끝나면 저절로 닫히고 `.finished`.
  /// `runModal`을 쓰지 않는다: 모달이 떠 있는 동안 메인 액터 작업이 멈춰 저장 재시도도, 저절로 닫기도 돌지 않았다.
  /// 그래서 알림 창을 보통 창처럼 띄우고 버튼을 직접 받는다.
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

  /// 작품을 열었는데 지난번에 작품 폴더에 쓰지 못한 원고가 작품 밖 백업에 남아 있다.
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

/// 늦은 저장 알림의 답. 버튼이든 저장 끝이든 먼저 온 것 하나만 받고 창을 닫는다.
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
