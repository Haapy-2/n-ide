import NovelCore
import SwiftUI

/// Editor area: reads only the selected episode's body in the background, loads it into the editor, and connects autosave and counting.
/// Below is the status bar (count, goal progress, save state).
struct EpisodeEditorPane: View {
  let autosaver: EpisodeAutosaver
  let counter: CharacterCounter
  let episodeID: EpisodeID
  let goal: Int
  /// This episode's last counted value. Shown right after opening until recounted. Read only when the episode opens.
  let knownCount: () -> CharacterCount?
  /// Go to a search result. Handled by the editor after this episode's body is loaded.
  var reveal: TextReveal?
  /// Once after this episode's body is loaded into the editor.
  var onShown: (EpisodeID) -> Void = { _ in }
  /// Message the editor shows the writer (toast).
  var onNotice: (String) -> Void = { _ in }
  @State private var content: ManuscriptEditor.Content?
  @State private var errorMessage: String?
  @State private var fade = StatusBarFade()
  /// Font, size, spacing and width changed in Settings. Changes apply to the open editor immediately.
  private var editorSettings = EditorStyleSettings()
  private var caretSettings = CaretStyleSettings()
  @AppStorage(AppSettingKey.characterCountInterval) private var countInterval = EditorSetting.characterCountInterval.defaultValue
  @AppStorage(AppSettingKey.statusBarHidesWhileTyping) private var hidesWhileTyping = false
  @AppStorage(AppSettingKey.statusBarHidesWhenIdle) private var hidesWhenIdle = true
  @AppStorage(AppSettingKey.autoSnapshotEnabled) private var autoSnapshot = true
  @AppStorage(AppSettingKey.autoSnapshotMinutes) private var snapshotMinutes = 30
  @AppStorage(AppSettingKey.snapshotRetention) private var snapshotRetention = 50
  @AppStorage(AppSettingKey.showsLineNumbers) private var showsLineNumbers = false
  @AppStorage(AppSettingKey.numbersBlankLines) private var numbersBlankLines = true
  @AppStorage(AppSettingKey.multiCursorEnabled) private var multiCursorEnabled = true

  var body: some View {
    let style = editorSettings.style
    // The status bar floats over the bottom of the body. When hidden its background goes too, so the body shows to the window bottom.
    ZStack(alignment: .bottom) {
      ZStack {
        Color.paper
        if let content {
          ManuscriptEditor(
            content: content,
            style: style,
            showsLineNumbers: showsLineNumbers,
            numbersBlankLines: numbersBlankLines,
            multiCursorEnabled: multiCursorEnabled,
            caret: caretSettings.style,
            reveal: reveal,
            onTextChange: {
              autosaver.textDidChange()
              fade.noteInput()
            },
            // The body is copied in place (the editor may vanish first as the window closes). Completion isn't awaited.
            onFocusLost: { autosaver.startSave() },
            onFocusGained: { Task { await autosaver.checkExternalChange() } },
            onReady: {
              autosaver.attach($0)
              counter.attach($0)
            },
            onNotice: onNotice,
            onShown: onShown)
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
    // Moving the mouse brings back a faded status bar. State changes only while hidden.
    .onContinuousHover { phase in
      if case .active = phase { fade.show() }
    }
    .onChange(of: episodeID, initial: true) { switchEpisode() }
    .onChange(of: countInterval, initial: true) {
      counter.interval = .milliseconds(Int(EditorSetting.characterCountInterval.clamped(countInterval) * 1_000))
    }
    // Changes apply immediately: the timer restarts when the interval or toggle changes.
    .onChange(of: [snapshotMinutes, snapshotRetention, autoSnapshot ? 1 : 0], initial: true) {
      autosaver.snapshots.settings = EpisodeSnapshotter.Settings(
        autoEnabled: autoSnapshot, minutes: snapshotMinutes, retention: snapshotRetention)
    }
    .onChange(of: [hidesWhileTyping, hidesWhenIdle], initial: true) {
      fade.hidesWhileTyping = hidesWhileTyping
      fade.hidesWhenIdle = hidesWhenIdle
      fade.reconsider()
    }
  }

  /// Episode switching happens in one go without waiting: saving the left episode only starts in the background,
  /// and the new body (~5,000 chars, ~0.1 ms) is read immediately and swapped within the same refresh.
  /// Waiting would leave the old body for a beat before switching, which looks choppy.
  private func switchEpisode() {
    autosaver.leaveEpisode()
    let id = episodeID
    do {
      // Use the in-memory body if any; otherwise read from disk and pass that file state as the external-change baseline.
      let pending = autosaver.pendingText(for: id)
      let version = pending == nil ? try autosaver.store.readEpisodeVersion(id) : nil
      errorMessage = nil
      let text = pending ?? version?.text ?? ""
      content = ManuscriptEditor.Content(token: UUID(), episodeID: id, text: text)
      autosaver.begin(episode: id, version: version)
      counter.begin(episode: id, text: text, known: knownCount())
    } catch let error as ProjectError {
      content = nil
      counter.clear()
      errorMessage = error.userMessage
    } catch {
      content = nil
      counter.clear()
      errorMessage = error.localizedDescription
    }
  }
}
