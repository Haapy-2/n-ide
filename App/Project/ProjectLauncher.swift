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
    openWindow(value: Self.windowValue(for: url))
    dismissWindow(id: AppScene.picker)
  }

  /// 창의 값으로 쓸 URL. 같은 작품 폴더는 어디서 열든(최근 목록, 열기 창, Finder) 같은 값이 되게 맞춘다.
  /// 끝의 `/` 하나만 달라도 다른 값이라 같은 작품이 창 두 개로 열리고, 두 창이 같은 파일을 따로 저장하게 된다.
  static func windowValue(for url: URL) -> URL {
    var path = url.standardizedFileURL.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return URL(filePath: path, directoryHint: .isDirectory)
  }
}

enum AppScene {
  static let picker = "project-picker"
}
