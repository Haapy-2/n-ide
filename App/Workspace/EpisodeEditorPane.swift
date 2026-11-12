import NovelCore
import SwiftUI

/// 편집 영역: 선택한 회차의 본문만 백그라운드에서 읽어 편집기에 올리고, 자동 저장기·글자 수 세기에 연결한다.
/// 아래에는 상태 줄(글자 수·목표 진행률·저장 상태).
struct EpisodeEditorPane: View {
  let autosaver: EpisodeAutosaver
  let counter: CharacterCounter
  let episodeID: EpisodeID
  let goal: Int
  /// project.json에 남아 있던 이 회차의 글자 수. 회차를 연 직전, 새로 세기 전까지 보여준다.
  let knownCount: CharacterCount?
  @State private var content: ManuscriptEditor.Content?
  @State private var errorMessage: String?
  @State private var fade = StatusBarFade()
  /// 설정 창에서 바꾼 글꼴·크기·간격·폭. 바뀌면 열려 있는 편집 영역에 바로 반영된다.
  private var editorSettings = EditorStyleSettings()

  var body: some View {
    let style = editorSettings.style
    VStack(spacing: 0) {
      ZStack {
        Color.paper
        if let content {
          ManuscriptEditor(
            content: content,
            style: style,
            onTextChange: {
              autosaver.textDidChange()
              fade.noteInput()
            },
            onFocusLost: { Task { await autosaver.flush() } },
            onFocusGained: { Task { await autosaver.checkExternalChange() } },
            onReady: {
              autosaver.attach($0)
              counter.attach($0)
            })
        } else if let errorMessage {
          Text(errorMessage)
            .font(.system(size: 13))
            .foregroundStyle(Color.error)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      StatusBar(counter: counter, autosaver: autosaver, fade: fade, goal: goal, textWidth: style.textWidth)
    }
    .background(Color.paper)
    // 마우스를 움직이면 흐려진 상태 줄이 다시 나타난다. 숨겨져 있을 때만 상태가 바뀐다.
    .onContinuousHover { phase in
      if case .active = phase { fade.show() }
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
      // 메모리에 남은 본문이 있으면 그것을, 없으면 디스크에서 읽고 그때의 파일 상태를 외부 변경 기준으로 넘긴다.
      let pending = autosaver.pendingText(for: id)
      let version = pending == nil ? try autosaver.store.readEpisodeVersion(id) : nil
      errorMessage = nil
      let text = pending ?? version?.text ?? ""
      content = ManuscriptEditor.Content(token: UUID(), episodeID: id, text: text)
      autosaver.begin(episode: id, version: version)
      counter.begin(episode: id, text: text, known: knownCount)
    } catch let error as ProjectError {
      content = nil
      errorMessage = error.userMessage
    } catch {
      content = nil
      errorMessage = error.localizedDescription
    }
  }
}
