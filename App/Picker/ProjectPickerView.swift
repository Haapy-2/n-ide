import SwiftUI

/// 앱을 열면 가장 먼저 뜨는 작품 선택 창 (Obsidian 볼트 선택처럼, DESIGN.md 4장).
struct ProjectPickerView: View {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var recent: [RecentProject]
  @State private var selection: RecentProject.ID?
  private let loadsRecentOnAppear: Bool

  /// - Parameter recent: 미리보기·스냅샷용. nil이면 앱 설정에서 읽는다.
  init(recent: [RecentProject]? = nil) {
    _recent = State(initialValue: recent ?? [])
    loadsRecentOnAppear = recent == nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(AppInfo.name)
        .font(.title2.weight(.semibold))

      Text("최근 작품")
        .font(.headline)
        .foregroundStyle(.secondary)

      if recent.isEmpty {
        Text("아직 작품이 없어요. 새 작품을 만들어 주세요.")
          .font(.system(size: 13))
          .foregroundStyle(Color.inkMuted)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        recentList
      }

      HStack(spacing: 12) {
        Button("새 작품…") { Task { await launcher.createNew() } }
          .keyboardShortcut(recent.isEmpty ? .defaultAction : nil)
        Button("다른 위치에서 열기…") { launcher.openExisting() }
      }
    }
    .padding(32)
    .frame(width: 560, height: 420)
    .onAppear {
      if loadsRecentOnAppear { recent = RecentProjects.load() }
    }
    // Finder에서 .novel을 두 번 클릭하면 여기로 들어온다.
    .onOpenURL { url in
      if url.isFileURL { launcher.open(url) }
    }
  }

  private var recentList: some View {
    List(recent, selection: $selection) { project in
      RecentProjectRow(project: project)
    }
    .contextMenu(forSelectionType: RecentProject.ID.self) { ids in
      if let project = recent.first(where: { ids.contains($0.id) }) {
        Button("Finder에서 보기") { SystemDialogs.revealInFinder(project.url) }
        Button("목록에서 빼기") {
          RecentProjects.remove(project)
          recent = RecentProjects.load()
        }
      }
    } primaryAction: { ids in
      // 두 번 클릭 또는 ↩
      if let project = recent.first(where: { ids.contains($0.id) }) { launcher.open(project.url) }
    }
  }

  private var launcher: ProjectLauncher {
    ProjectLauncher(openWindow: openWindow, dismissWindow: dismissWindow)
  }
}

/// 최근 작품 한 줄: 제목과 `212화 · 어제`, 아래에 폴더 경로.
private struct RecentProjectRow: View {
  let project: RecentProject

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(project.title)
          .font(.system(size: 13))
          .lineLimit(1)
        Spacer()
        Text("\(project.episodeCount)화 · \(project.lastOpened.formatted(.relative(presentation: .named)))")
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(Color.inkMuted)
      }
      Text(abbreviatedPath)
        .font(.system(size: 11))
        .foregroundStyle(Color.inkMuted)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(.vertical, 3)
  }

  /// 홈 폴더를 `~`로 줄인다.
  private var abbreviatedPath: String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    let path = project.path
    return path.hasPrefix(home) ? "~/" + path.dropFirst(home.count) : path
  }
}

#Preview("빈 목록") {
  ProjectPickerView(recent: [])
}

#Preview("최근 작품") {
  ProjectPickerView(recent: [
    RecentProject(path: "/Users/me/Documents/달빛 아래 검.novel", title: "달빛 아래 검", episodeCount: 212, lastOpened: .now.addingTimeInterval(-86_400)),
    RecentProject(path: "/Users/me/Desktop/시험용 단편.novel", title: "시험용 단편", episodeCount: 3, lastOpened: .now.addingTimeInterval(-86_400 * 8)),
  ])
}
