import NovelCore
import SwiftUI

/// 작품 하나의 작업 공간: 유리 사이드바(회차 목록) + 불투명 종이 편집 영역.
/// 편집기는 5단계에서 편집 영역에 들어간다.
struct WorkspaceView: View {
  let project: ProjectFile
  @State private var selection: EpisodeID?

  init(project: ProjectFile) {
    self.project = project
    _selection = State(initialValue: project.episodes.first?.id)
  }

  var body: some View {
    NavigationSplitView {
      EpisodeList(episodes: project.episodes, selection: $selection)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    } detail: {
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        // 종이색이 떠 있는 유리 사이드바 아래까지 이어져 보이게 한다 (DESIGN.md 0장).
        .backgroundExtensionEffect()
        // 제목과 버튼을 편집 영역 쪽 툴바에 붙인다. 사이드바 쪽에 두면 사이드바 폭만큼만 보여서 긴 제목이 잘린다.
        .navigationTitle(project.title)
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
    }
    .frame(minWidth: 720, minHeight: 480)
  }

  @ViewBuilder
  private var detail: some View {
    if project.episodes.isEmpty {
      EmptyStateView(message: "첫 회차를 추가해 주세요.", buttonTitle: "새 회차", action: nil)
    } else {
      // 편집기 자리 (5단계)
      Color.clear
    }
  }
}

// Xcode 캔버스(⌥⌘↩)에서 작업 공간을 바로 볼 수 있다.
#Preview("빈 작품") {
  WorkspaceView(project: ProjectFile(title: "회귀한 검성은 이번 생에서만큼은 조용히 살고 싶다"))
    .frame(width: 1100, height: 760)
}

#Preview("500회차") {
  WorkspaceView(project: .previewManyEpisodes)
    .frame(width: 1100, height: 760)
}

extension ProjectFile {
  /// 미리보기와 스냅샷용 500회차 작품 (본문 없음).
  static var previewManyEpisodes: ProjectFile {
    let titles = ["귀환", "비 오는 날", "", "검의 무게", "첫 번째 의뢰", "달빛 아래에서"]
    return ProjectFile(
      title: "달빛 아래 검",
      episodes: (0..<500).map { EpisodeMeta(title: titles[$0 % titles.count], goal: 5_000) })
  }
}
