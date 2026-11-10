import SwiftUI

/// 작품 하나의 작업 공간 창: 유리 사이드바 + 불투명 종이 편집 영역.
/// 1단계에서는 틀만 있다. 회차 목록은 4단계, 편집기는 5단계에서 채운다.
struct WorkspaceView: View {
  let projectTitle: String

  var body: some View {
    NavigationSplitView {
      List {
        Section("회차") {}
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    } detail: {
      EmptyStateView(message: "첫 회차를 추가해 주세요.", buttonTitle: "새 회차", action: nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        // 종이색이 떠 있는 유리 사이드바 아래까지 이어져 보이게 한다 (DESIGN.md 0장).
        .backgroundExtensionEffect()
    }
    .navigationTitle(projectTitle)
    .toolbar {
      ToolbarItem {
        Button("새 회차", systemImage: "square.and.pencil") {}
          .disabled(true)
      }
      ToolbarItem {
        Button("노트 나란히 보기", systemImage: "sidebar.right") {}
          .disabled(true)
      }
    }
    .frame(minWidth: 720, minHeight: 480)
  }
}

// Xcode 캔버스(⌥⌘↩)에서 작업 공간 틀을 바로 볼 수 있다. 4단계 전까지 앱에서는 이 화면으로 갈 수 없다.
#Preview {
  WorkspaceView(projectTitle: "달빛 아래 검")
    .frame(width: 1100, height: 760)
}
