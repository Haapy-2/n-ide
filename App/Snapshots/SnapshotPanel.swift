import NovelCore
import SwiftUI

/// 작업 공간 위에 뜨는 스냅샷 판(⇧⌘S, PLAN 10장 5번, 참고 이미지 11-ref-floating-panel.png).
/// 뒤를 살짝 어둡게 덮고, 판 바깥을 누르거나 Esc·✕로 닫는다. 왼쪽 스냅샷 목록, 오른쪽 과거↔현재 비교.
/// 크기는 창 크기를 따라간다(고정 값 없이 실행 중에 잰 창 크기의 비율).
struct SnapshotPanel: View {
  let browser: SnapshotBrowser
  let title: String
  /// 외부 변경 충돌을 아직 고르지 않았으면 되돌리기를 막는다(PLAN 10장 6번).
  var hasConflict = false
  let onClose: () -> Void
  var onRestore: () -> Void = {}
  @State private var editingMemoID: String?

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
        // 메모를 고치는 중에는 Esc가 메모 고치기만 그만두게 한다.
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
    // 판 안의 빈 곳을 눌러도 뒤 막의 "누르면 닫기"가 받지 않게, 판 전체를 누를 수 있는 곳으로 둔다.
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
