import SwiftUI

/// 빈 화면: 짧은 안내 한 줄과 버튼 하나. 일러스트나 아이콘은 넣지 않는다 (DESIGN.md 4장).
struct EmptyStateView: View {
  let message: String
  let buttonTitle: String
  let action: (() -> Void)?

  var body: some View {
    VStack(spacing: 14) {
      Text(message)
        .font(.system(size: 13))
        .foregroundStyle(Color.inkMuted)
      Button(buttonTitle) { action?() }
        .disabled(action == nil)
    }
  }
}
