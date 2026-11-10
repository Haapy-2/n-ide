import NovelCore
import SwiftUI

/// 편집 영역: 선택한 회차의 본문만 백그라운드에서 읽어 편집기에 올린다.
/// 저장은 6단계에서 붙는다. 지금은 회차를 바꾸면 고친 내용이 사라진다.
struct EpisodeEditorPane: View {
  let store: ProjectStore
  let episodeID: EpisodeID
  @State private var content: ManuscriptEditor.Content?
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      Color.paper
      if let content {
        ManuscriptEditor(content: content)
      } else if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 13))
          .foregroundStyle(Color.error)
          .padding(40)
      }
    }
    .task(id: episodeID) { await load() }
  }

  private func load() async {
    let store = store
    let id = episodeID
    do {
      // 파일 읽기는 메인 스레드 밖에서.
      let text = try await Task.detached { try store.readEpisode(id) }.value
      guard id == episodeID else { return }
      errorMessage = nil
      content = ManuscriptEditor.Content(token: UUID(), episodeID: id, text: text)
    } catch let error as ProjectError {
      content = nil
      errorMessage = error.userMessage
    } catch {
      content = nil
      errorMessage = error.localizedDescription
    }
  }
}
