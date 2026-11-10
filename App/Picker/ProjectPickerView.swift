import SwiftUI

/// 앱을 열면 가장 먼저 뜨는 작품 선택 창 (Obsidian 볼트 선택처럼).
/// 1단계에서는 빈 상태만 보여준다. 최근 작품 목록과 버튼 동작은 4단계에서 붙인다.
struct ProjectPickerView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(AppInfo.name)
        .font(.title2.weight(.semibold))

      Text("최근 작품")
        .font(.headline)
        .foregroundStyle(.secondary)

      Text("아직 작품이 없어요. 새 작품을 만들어 주세요.")
        .font(.system(size: 13))
        .foregroundStyle(Color.inkMuted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      HStack(spacing: 12) {
        Button("새 작품…") {}
          .keyboardShortcut(.defaultAction)
        Button("다른 위치에서 열기…") {}
      }
      .disabled(true)
    }
    .padding(32)
    .frame(width: 560, height: 420)
  }
}
