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

  /// 주어진 폭에서 미리보기 문장이 다 들어가는 높이.
  /// 화면에 보이는 뷰의 글 상자를 건드리지 않고 따로 만든 글 상자로 잰다. 전에는 잴 때마다 보이는 뷰의 글 상자 폭을
  /// 바꿔서, 마지막으로 잰 폭(더 좁은 폭)이 남아 줄이 일찍 꺾이고 높이는 넓은 폭 기준이라 아래가 잘렸다(2026-11-12 사용자 지적).
  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
    let width = proposal.width ?? 400
    let storage = NSTextStorage(string: Self.sample, attributes: style.textAttributes)
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: max(width - Self.inset.width * 2, 50), height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = view.textContainer?.lineFragmentPadding ?? 5
    layoutManager.addTextContainer(container)
    layoutManager.ensureLayout(for: container)
    let height = layoutManager.usedRect(for: container).height + Self.inset.height * 2
    return CGSize(width: width, height: ceil(height))
  }

  private func apply(_ style: EditorStyle, to view: NSTextView) {
    view.textStorage?.setAttributedString(NSAttributedString(string: Self.sample, attributes: style.textAttributes))
  }
}
