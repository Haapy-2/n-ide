import NovelCore
import SwiftUI

/// 작업 공간 창 하나: 작품 폴더를 백그라운드에서 열고(필요하면 복구), 다 열리면 작업 공간을 보여준다.
struct WorkspaceWindow: View {
  let url: URL
  @Environment(\.openWindow) private var openWindow
  @State private var state: LoadState = .loading
  @State private var recoveryNotice: String?

  private enum LoadState {
    case loading
    case loaded(ProjectModel)
    case failed(String)
  }

  var body: some View {
    Group {
      switch state {
      case .loading:
        // 목표가 0.3초 이내라 안내 문구 없이 종이만 잠깐 보인다.
        Color.paper.frame(minWidth: 720, minHeight: 480)
      case .loaded(let model):
        WorkspaceView(model: model)
      case .failed(let message):
        EmptyStateView(message: message, buttonTitle: "작품 전환…") { openWindow(id: AppScene.picker) }
          .padding(40)
          .frame(minWidth: 720, minHeight: 480)
          .background(Color.paper)
      }
    }
    .navigationTitle(url.deletingPathExtension().lastPathComponent)
    .task(id: url) { await load() }
    .alert("작품 정보를 복구했어요", isPresented: .constant(recoveryNotice != nil)) {
      Button("확인") { recoveryNotice = nil }
    } message: {
      Text(recoveryNotice ?? "")
    }
  }

  private func load() async {
    let url = url
    do {
      // 파일 읽기와 복구는 메인 스레드 밖에서.
      let (project, recovery) = try await Task.detached { try ProjectStore(root: url).open() }.value
      RecentProjects.record(url: url, title: project.title, episodeCount: project.episodes.count)
      recoveryNotice = Self.notice(for: recovery)
      state = .loaded(ProjectModel(project: project, store: ProjectStore(root: url)))
    } catch let error as ProjectError {
      state = .failed(error.userMessage)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  private static func notice(for recovery: ProjectRecovery) -> String? {
    switch recovery {
    case .none:
      nil
    case .fromBackup:
      "project.json이 손상되어 직전 백업으로 되살렸어요. 손상된 파일은 작품 폴더에 project.json.broken-…으로 남겨 두었어요."
    case .rebuiltFromFiles:
      "project.json과 백업을 모두 읽을 수 없어 회차 파일로 목록을 다시 만들었어요. 본문은 그대로지만 회차 순서와 제목은 확인해 주세요."
    }
  }
}
