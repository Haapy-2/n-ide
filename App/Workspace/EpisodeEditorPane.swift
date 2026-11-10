import NovelCore
import SwiftUI

/// 편집 영역: 선택한 회차의 본문만 백그라운드에서 읽어 편집기에 올리고, 자동 저장기에 연결한다.
struct EpisodeEditorPane: View {
  let autosaver: EpisodeAutosaver
  let episodeID: EpisodeID
  @State private var content: ManuscriptEditor.Content?
  @State private var errorMessage: String?

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Color.paper
      if let content {
        ManuscriptEditor(
          content: content,
          onTextChange: { autosaver.textDidChange() },
          onFocusLost: { Task { await autosaver.flush() } },
          onReady: { autosaver.attach($0) })
      } else if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 13))
          .foregroundStyle(Color.error)
          .padding(40)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      SaveStatusLabel(autosaver: autosaver)
        .padding(.trailing, 20)
        .padding(.bottom, 10)
    }
    .onChange(of: episodeID, initial: true) { switchEpisode() }
  }

  /// 회차 전환은 기다림 없이 한 번에 한다: 떠나는 회차 저장은 뒤에서 시작만 하고,
  /// 새 회차 본문(5,000자 안팎, 0.1ms 수준)은 바로 읽어 같은 화면 갱신 안에서 바꿔 넣는다.
  /// 기다리는 동안 옛 본문이 한 박자 남아 있다가 바뀌면 끊겨 보이기 때문이다.
  private func switchEpisode() {
    autosaver.leaveEpisode()
    let id = episodeID
    do {
      let text = try autosaver.pendingText(for: id) ?? autosaver.store.readEpisode(id)
      errorMessage = nil
      content = ManuscriptEditor.Content(token: UUID(), episodeID: id, text: text)
      autosaver.begin(episode: id)
    } catch let error as ProjectError {
      content = nil
      errorMessage = error.userMessage
    } catch {
      content = nil
      errorMessage = error.localizedDescription
    }
  }
}

/// 저장 상태: 평소엔 비어 있고, 오래 걸리는 저장과 실패만 보인다(DESIGN.md 4장 상태 줄).
/// 9단계에서 상태 줄로 옮겨 간다.
private struct SaveStatusLabel: View {
  let autosaver: EpisodeAutosaver

  var body: some View {
    switch autosaver.status {
    case .failed(let message):
      Text("저장 실패 · 원고는 메모리에 있음")
        .font(.system(size: 11))
        .foregroundStyle(Color.error)
        .help(message)
    case .saving where autosaver.showsSavingIndicator:
      Text("저장 중…")
        .font(.system(size: 11))
        .foregroundStyle(Color.inkMuted)
    default:
      EmptyView()
    }
  }
}
