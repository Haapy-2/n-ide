import SwiftUI

extension Color {
  static let rowSelected = Color.ink.opacity(0.08)
  /// Gray rect for the hovered row. Half intensity so it isn't confused with the selection.
  static let rowHovered = Color.ink.opacity(0.04)
}

/// Row background shared by the sidebar episode list and the project picker: darker gray when selected, lighter gray on hover.
///
/// Hover state is kept per row, so mouse movement redraws only that row, not the whole list.
private struct RowHighlight: ViewModifier {
  let isSelected: Bool
  @State private var isHovered = false

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isSelected ? Color.rowSelected : isHovered ? Color.rowHovered : .clear))
      .onHover { isHovered = $0 }
  }
}

extension View {
  func rowHighlight(isSelected: Bool) -> some View {
    modifier(RowHighlight(isSelected: isSelected))
  }
}
