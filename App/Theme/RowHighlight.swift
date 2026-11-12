import SwiftUI

extension Color {
  /// 선택한 줄의 회색 칸.
  static let rowSelected = Color.ink.opacity(0.08)
  /// 마우스를 올린 줄의 회색 칸. 선택 칸과 헷갈리지 않게 절반 진하기(2026-11-12 사용자 결정).
  static let rowHovered = Color.ink.opacity(0.04)
}

/// 사이드바 회차 목록과 작품 선택 창이 함께 쓰는 줄 배경: 선택이면 진한 회색 칸, 마우스를 올리면 연한 회색 칸.
///
/// 마우스 상태를 줄마다 따로 두어서, 마우스가 움직일 때 목록 전체가 아니라 그 줄만 다시 그려진다.
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
