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
      if let url = LaunchProbe.projectToOpen { launcher.open(url) }
      if loadsRecentOnAppear { recent = RecentProjects.load() }
    }
    // Finder에서 .novel을 두 번 클릭하면 여기로 들어온다.
    .onOpenURL { url in
      if url.isFileURL { launcher.open(url) }
    }
  }

  /// 선택 표시는 작업 공간 사이드바와 같은 직접 그린 회색 칸(시스템 파란 선택 대신, DESIGN.md 4장).
  /// 한 번 클릭하면 선택, 두 번 클릭하면 열기, 선택한 채로 ↩를 눌러도 열린다.
  private var recentList: some View {
    List {
      ForEach(recent) { project in
        RecentProjectRow(project: project)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .rowHighlight(isSelected: project.id == selection)
          .contentShape(RoundedRectangle(cornerRadius: 6))
          // 한 번 클릭 선택은 바로 처리한다. 두 제스처를 순서대로 붙이면 SwiftUI가 "두 번 클릭인지"
          // 판정 시간(약 0.3~0.5초)을 기다린 뒤에야 선택해서 클릭이 굼떠 보인다.
          .onTapGesture(count: 2) { launcher.open(project.url) }
          .simultaneousGesture(TapGesture().onEnded { selection = project.id })
          .contextMenu {
            Button("Finder에서 보기") { SystemDialogs.revealInFinder(project.url) }
            Button("목록에서 빼기") {
              RecentProjects.remove(project)
              recent = RecentProjects.load()
            }
          }
          .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
    }
    .scrollContentBackground(.hidden)
    .onKeyPress(.return) {
      guard let project = recent.first(where: { $0.id == selection }) else { return .ignored }
      launcher.open(project.url)
      return .handled
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

  /// 홈 폴더를 `~`로 줄이고, 폴더 경로 끝의 `/`는 뺀다.
  private var abbreviatedPath: String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    var path = project.path
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
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
