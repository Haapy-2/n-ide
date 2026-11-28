import NovelCore
import SwiftUI

/// Snapshot panel floating over the workspace (⇧⌘S, PLAN ch.10 #5, reference 11-ref-floating-panel.png).
/// Lightly dims the background; closes on a click outside, Esc or ✕. Snapshot list on the left, past↔present diff on the right.
/// Size follows the window (a ratio of the window size measured at runtime, no fixed values).
struct SnapshotPanel: View {
  let browser: SnapshotBrowser
  let title: String
  /// Restore is blocked while an external-change conflict is unresolved (PLAN ch.10 #6).
  var hasConflict = false
  let onClose: () -> Void
  var onRestore: () -> Void = {}
  @State private var editingMemoID: String?
  @FocusState private var hasFocus: Bool

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.scrim
          .contentShape(Rectangle())
          .onTapGesture { onClose() }
          .accessibilityHidden(true)
        panel(listWidth: min(max(proxy.size.width * 0.22, 200), 280))
          .frame(width: proxy.size.width * 0.92, height: proxy.size.height * 0.9)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    // While the panel is open the editor releases focus, so ⌘Z climbed to the window's history (sidebar episode actions) and undid without confirmation.
    // The panel must take focus so these commands reach it first (with focus only on the window, onCommand isn't reached). Nothing happens while the panel is up.
    .focusable()
    .focusEffectDisabled()
    .focused($hasFocus)
    .onAppear { hasFocus = true }
    .onCommand(Selector(("undo:"))) {}
    .onCommand(Selector(("redo:"))) {}
    .alert("이 스냅샷을 지킬까요?", isPresented: isAskingToKeep, presenting: browser.askingToKeep) { id in
      Button("지키기") { browser.keep(id) }
      Button("지키지 않기", role: .cancel) {}
    } message: { _ in
      Text("이름 변경 스냅샷은 메모가 있어도 보관 개수를 넘으면 오래된 것부터 지워져요. 지키면 개수에 세지 않고 지우지 않아요.")
    }
  }

  private var isAskingToKeep: Binding<Bool> {
    Binding(get: { browser.askingToKeep != nil }, set: { if !$0 { browser.askingToKeep = nil } })
  }

  private func panel(listWidth: CGFloat) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.ink)
          .lineLimit(1)
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.inkMuted)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("닫기 (Esc)")
        .accessibilityLabel("닫기")
        // While editing a memo, Esc only cancels the memo edit.
        .keyboardShortcut(editingMemoID == nil ? .cancelAction : nil)
      }
      .padding(.leading, 16)
      .padding(.trailing, 10)
      .padding(.vertical, 8)
      Rectangle().fill(Color.rule).frame(height: 1)
      HStack(spacing: 0) {
        SnapshotListView(browser: browser, editingID: $editingMemoID)
          .frame(width: listWidth)
        Rectangle().fill(Color.rule).frame(width: 1)
        detail
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Rectangle().fill(Color.rule).frame(height: 1)
      HStack(spacing: 12) {
        if let message = browser.errorMessage {
          Text(message)
            .font(.system(size: 12))
            .foregroundStyle(Color.error)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        if let title = browser.restoredTitle {
          Text("제목도 되돌려요: \(title.isEmpty ? "제목 없음" : title)")
            .font(.system(size: 12))
            .foregroundStyle(Color.inkMuted)
            .lineLimit(1)
        }
        Button("이 버전으로 되돌리기", action: onRestore)
          .disabled(hasConflict || !browser.canRestore)
          .help(restoreHelp)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .background(Color.paper)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.rule))
    // The whole panel is made clickable so clicks on its blank areas aren't taken by the backdrop's "click to close".
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var detail: some View {
    switch browser.comparison {
    case .ready(let diff):
      DiffView(diff: diff, pastTitle: pastTitle)
    case .failed(let message):
      Text(message)
        .font(.system(size: 12))
        .foregroundStyle(Color.error)
    case .comparing:
      ProgressView().controlSize(.small)
    case .idle:
      Color.clear
    }
  }

  private var restoreHelp: String {
    if hasConflict { return "바깥에서 바뀐 내용을 먼저 골라 주세요" }
    if case .ready(let diff) = browser.comparison, !diff.hasChanges { return "지금 글과 같아요" }
    return "지금 글은 ‘복원 전’ 스냅샷으로 남아요"
  }

  private var pastTitle: String {
    guard let date = browser.selected?.snapshot.date else { return "과거" }
    return "과거 · \(date.formatted(.dateTime.month().day())) \(SnapshotListView.time(date))"
  }
}
