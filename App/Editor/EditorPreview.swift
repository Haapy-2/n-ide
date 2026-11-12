import AppKit
import SwiftUI

/// 설정 창의 미리보기: 편집기와 같은 모양 값(`EditorStyle.textAttributes`)으로 짧은 원고를 종이 위에 보여준다.
/// 고칠 수 없고, 폭은 설정 창에 맞춰 줄바꿈된다(본문 폭 설정은 숫자로만 보인다).
struct EditorPreview: NSViewRepresentable {
  let style: EditorStyle

  static let sample = """
    비가 그친 골목에는 아직 물 냄새가 남아 있었다.
    "여기서 뭐 해요?" 돌아보니 젖은 소녀가 서 있었다.
    """

  /// 종이 안쪽 여백
  private static let inset = NSSize(width: 20, height: 16)

  func makeNSView(context: Context) -> NSTextView {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)
    let view = NSTextView(frame: .zero, textContainer: container)
    view.isEditable = false
    view.isSelectable = false
    view.drawsBackground = true
    view.backgroundColor = .paper
    view.textContainerInset = Self.inset
    apply(style, to: view)
    return view
  }

  func updateNSView(_ view: NSTextView, context: Context) {
    apply(style, to: view)
    view.invalidateIntrinsicContentSize()
  }

  /// 주어진 폭에서 미리보기 문장이 다 들어가는 높이. 글자 크기·간격이 바뀌면 높이도 따라 바뀐다.
  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
    let width = proposal.width ?? 400
    guard let container = view.textContainer, let layoutManager = view.layoutManager else { return nil }
    container.size = NSSize(width: max(width - Self.inset.width * 2, 50), height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    let height = layoutManager.usedRect(for: container).height + Self.inset.height * 2
    return CGSize(width: width, height: ceil(height))
  }

  private func apply(_ style: EditorStyle, to view: NSTextView) {
    view.textStorage?.setAttributedString(NSAttributedString(string: Self.sample, attributes: style.textAttributes))
  }
}
