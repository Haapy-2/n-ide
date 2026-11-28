import AppKit
import SwiftUI

/// Settings preview: shows a short manuscript on paper with the same style values as the editor (`EditorStyle.textAttributes`).
/// Not editable; wraps to the Settings window width (the body width setting shows only as a number).
struct EditorPreview: NSViewRepresentable {
  let style: EditorStyle

  static let sample = """
    비가 그친 골목에는 아직 물 냄새가 남아 있었다.
    "여기서 뭐 해요?" 돌아보니 젖은 소녀가 서 있었다.
    """

  /// Inner padding of the paper
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

  /// Height that fits the whole preview text at the given width.
  /// Measured with a separate text container instead of the visible view's. Resizing the visible view to measure
  /// leaves the last measured (narrower) width behind, so lines wrap early while height uses the wide width and the bottom gets cut.
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
