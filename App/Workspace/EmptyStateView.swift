import SwiftUI

/// Empty state: one short line of guidance and one button. No illustrations or icons (DESIGN.md ch.4).
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
