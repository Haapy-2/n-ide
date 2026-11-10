import NovelCore
import SwiftUI

/// 새 작품 만들기와 작품 열기의 공통 흐름. 작품 선택 창과 파일 메뉴가 함께 쓴다.
struct ProjectLauncher {
  let openWindow: OpenWindowAction
  let dismissWindow: DismissWindowAction

  /// 위치를 묻고 새 작품 폴더를 만든 뒤 연다.
  func createNew() async {
    guard let url = SystemDialogs.askNewProjectLocation() else { return }
    let title = url.deletingPathExtension().lastPathComponent
    do {
      // 파일 쓰기는 메인 스레드 밖에서.
      try await Task.detached { _ = try ProjectStore.create(at: url, title: title) }.value
      open(url)
    } catch let error as ProjectError {
      SystemDialogs.showError("새 작품을 만들지 못했어요", message: error.userMessage)
    } catch {
      SystemDialogs.showError("새 작품을 만들지 못했어요", message: error.localizedDescription)
    }
  }

  func openExisting() {
    if let url = SystemDialogs.askExistingProject() { open(url) }
  }

  /// 작업 공간 창을 열고 작품 선택 창을 닫는다. 같은 작품이 이미 열려 있으면 그 창이 앞으로 온다.
  func open(_ url: URL) {
    openWindow(value: url.standardizedFileURL)
    dismissWindow(id: AppScene.picker)
  }
}

enum AppScene {
  static let picker = "project-picker"
}
