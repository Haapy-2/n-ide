import SwiftUI

/// 설정 창(⌘,) (DESIGN.md 4장 "설정 창"). 왼쪽 목록에서 섹션을 고르면 오른쪽에 그 설정이 보인다.
/// 앱 전체 설정이라 UserDefaults에 저장되고(목표만 작품별), 바꾸면 열린 창들에 바로 반영된다.
/// 창 크기는 고정이다(2026-11-12 사용자 요청). 열 때마다 "일반"부터 보인다.
struct SettingsView: View {
  /// 왼쪽 목록 180 + 오른쪽 520. 오른쪽 폭은 슬라이더(240)와 이름이 넉넉한 예전 설정 창 폭.
  /// 높이는 가장 긴 "편집기"가 스크롤 없이 들어가고 13인치 화면에도 들어가는 값(스냅샷으로 확인).
  static let windowSize = CGSize(width: 700, height: 640)
  static let sidebarWidth: CGFloat = 180

  @State private var section: SettingsSection? = .general

  init(section: SettingsSection = .general) {
    _section = State(initialValue: section)
  }

  var body: some View {
    NavigationSplitView {
      List(SettingsSection.allCases, selection: $section) { item in
        // Label 기본 간격은 답답해 보여서 아이콘과 이름 사이를 직접 띄운다(2026-11-12 사용자 요청).
        // 아이콘 칸 폭을 같게 두어 이름의 왼쪽 끝이 한 줄로 맞는다.
        HStack(spacing: 10) {
          // 색 없는 아이콘: 라이트에서는 진한 회색, 다크에서는 밝은 회색(시스템 보조 글자색, 사용자 요청)
          Image(systemName: item.symbolName)
            .foregroundStyle(.secondary)
            .frame(width: 20)
          Text(item.title)
        }
        .padding(.vertical, 2)
      }
      .navigationSplitViewColumnWidth(Self.sidebarWidth)
      // 창이 고정 크기라 목록을 접을 일이 없다.
      .toolbar(removing: .sidebarToggle)
    } detail: {
      switch section ?? .general {
      case .general: GeneralSettingsPane()
      case .editor: EditorSettingsPane()
      case .sidebar: SidebarSettingsPane()
      }
    }
    .navigationTitle((section ?? .general).title)
    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
  }
}

/// 설정 창 왼쪽 목록의 섹션. 순서는 사용자가 정한 그대로(2026-11-12).
enum SettingsSection: String, CaseIterable, Identifiable {
  case general, editor, sidebar

  var id: Self { self }

  var title: String {
    switch self {
    case .general: "일반"
    case .editor: "편집기"
    case .sidebar: "사이드바"
    }
  }

  var symbolName: String {
    switch self {
    case .general: "gearshape"
    case .editor: "textformat"
    case .sidebar: "sidebar.left"
    }
  }
}
