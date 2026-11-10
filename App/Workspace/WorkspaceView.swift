import NovelCore
import SwiftUI

/// 작품 하나의 작업 공간: 유리 사이드바(회차 목록) + 불투명 종이 편집 영역.
struct WorkspaceView: View {
  let project: ProjectFile
  /// nil이면 본문을 읽지 않는다(미리보기·스냅샷용).
  @State private var autosaver: EpisodeAutosaver?
  @State private var selection: EpisodeID?

  init(project: ProjectFile, store: ProjectStore? = nil) {
    self.project = project
    _autosaver = State(initialValue: store.map { EpisodeAutosaver(store: $0) })
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
    // 창을 닫을 때 남은 저장을 마친다(Task가 저장기를 붙잡고 있어 창이 사라져도 끝까지 저장된다).
    .onDisappear { if let autosaver { Task { await autosaver.flush() } } }
  }

  @ViewBuilder
  private var detail: some View {
    if project.episodes.isEmpty {
      EmptyStateView(message: "첫 회차를 추가해 주세요.", buttonTitle: "새 회차", action: nil)
    } else if let autosaver, let selection {
      EpisodeEditorPane(autosaver: autosaver, episodeID: selection)
    } else {
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
