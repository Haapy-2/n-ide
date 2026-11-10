import AppKit

/// 앱 종료 때 진행 중이거나 남은 저장을 끝까지 마치고 끈다(SPEC 6장).
/// SwiftUI에는 종료를 잠시 미루는 방법이 없어서 AppKit 앱 대리자를 쓴다(AppKit 예외 파일).
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let autosavers = AutosaverRegistry.shared.all
    guard autosavers.contains(where: \.hasUnsavedChanges) else { return .terminateNow }
    Task { @MainActor in
      for autosaver in autosavers { await autosaver.flush() }
      if autosavers.contains(where: \.hasUnsavedChanges) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "저장하지 못한 원고가 있어요"
        alert.informativeText = "지금 끄면 마지막으로 고친 내용이 사라져요. 디스크 공간과 작품 폴더 권한을 확인한 뒤 다시 시도해 주세요."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "그래도 종료")
        sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
      } else {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }
}
