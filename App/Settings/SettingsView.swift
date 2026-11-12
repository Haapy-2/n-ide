import SwiftUI

/// 설정 창(⌘,) (DESIGN.md 4장 "설정 창"). 왼쪽 목록에서 섹션을 고르면 오른쪽에 그 설정이 보인다.
/// 앱 전체 설정이라 UserDefaults에 저장되고(목표만 작품별), 바꾸면 열린 창들에 바로 반영된다.
/// 창 크기는 고정이다(2026-11-12 사용자 요청). 열 때마다 "일반"부터 보인다.
struct SettingsView: View {
  /// 왼쪽 목록 180 + 오른쪽 520. 오른쪽 폭은 슬라이더(240)와 이름이 넉넉한 예전 설정 창 폭.
  /// 높이는 가장 긴 "편집기"가 스크롤 없이 들어가고 13인치 화면에도 들어가는 값(스냅샷으로 확인).
  static let windowSize = CGSize(width: 700, height: 640)
  static let sidebarWidth: CGFloat = 180

  @State private var section: SettingsSection = .general
  /// 목록 줄의 가로 배치. 실행 중에 창 닫기 버튼 위치를 재서 정한다. 재기 전에는 nil.
  @State private var layout: RowLayout?

  init(section: SettingsSection = .general) {
    _section = State(initialValue: section)
  }

  var body: some View {
    NavigationSplitView {
      // 시스템 List 대신 줄을 직접 쌓는다(2026-11-12 사용자 선택 1번): List는 줄을 패널 왼쪽 16pt부터만 그려서
      // 아이콘을 빨간 닫기 버튼(창 왼쪽 9pt) 선까지 옮길 수 없었다. 선택·마우스 올림·클릭은 원래 직접 그려서 잃는 기능은 없다.
      // 시스템 선택(파란 강조색 칸) 대신 작업 공간 사이드바와 같은 회색 칸을 직접 그린다(2026-11-12 사용자 결정).
      VStack(spacing: 0) {
        ForEach(SettingsSection.allCases) { item in
          // 아이콘은 빨간 닫기 버튼과 같은 선, 이름은 아이콘 오른쪽에 왼쪽 정렬(2026-11-12 사용자 요청).
          // 간격은 따로 정하지 않고 시스템 기본(예전 15pt는 없앰). 이름 가운데 정렬은 해 보고 되돌림(사용자).
          HStack {
            // 색 없는 아이콘: 라이트에서는 진한 회색, 다크에서는 밝은 회색(시스템 보조 글자색, 사용자 요청)
            // 아이콘 칸 폭을 같게 두어 이름의 왼쪽 끝이 한 줄로 맞는다. 아이콘은 칸 왼쪽에 붙여 버튼 선을 지킨다.
            // 잰 값이 오기 전에는 숨긴다: 기본 위치에 한 번 그렸다가 옮겨지는 것이 보이지 않게(사용자 선택).
            Image(systemName: item.symbolName)
              .foregroundStyle(.secondary)
              .frame(width: 20, alignment: .leading)
              .opacity(layout == nil ? 0 : 1)
            Text(item.title)
          }
          .padding(.leading, layout?.iconPadding ?? 0)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .rowHighlight(isSelected: item == section)
          .padding(.horizontal, layout?.boxMargin ?? 0)
          // 칸 사이 틈까지 눌리게(작업 공간 사이드바와 같은 이유)
          .padding(.vertical, 1)
          .contentShape(Rectangle())
          .onTapGesture { section = item }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(item == section ? [.isButton, .isSelected] : .isButton)
        }
        Spacer(minLength: 0)
      }
      // 패널 왼쪽 끝에서 한 번 잰다(줄마다 잴 필요 없음). 패널 끝은 여백과 상관없이 고정이라 잰 값이 흔들리지 않는다.
      .background(TrafficLightOffsetReader { offset in
        layout = RowLayout(buttonOffset: TrafficLightOffsetReader.contentInset(for: offset))
      })
      .navigationSplitViewColumnWidth(Self.sidebarWidth)
      // 창이 고정 크기라 목록을 접을 일이 없다.
      .toolbar(removing: .sidebarToggle)
    } detail: {
      switch section {
      case .general: GeneralSettingsPane()
      case .editor: EditorSettingsPane()
      case .sidebar: SidebarSettingsPane()
      }
    }
    .navigationTitle(section.title)
    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
  }
}

/// 설정 창 왼쪽 목록 줄의 가로 배치. 패널 왼쪽 끝 → 닫기 버튼 거리를 반씩 나눠
/// 앞 절반은 패널 끝과 회색 칸 사이, 뒤 절반은 회색 칸 끝과 아이콘 사이로 쓴다. 그래서 아이콘 왼쪽 끝 = 버튼 왼쪽 끝.
/// 숫자를 박지 않는 이유는 작업 공간 사이드바와 같다(macOS 버전·창 모양에 따라 버튼 위치가 다르다).
private struct RowLayout: Equatable {
  let boxMargin: CGFloat
  let iconPadding: CGFloat

  init(buttonOffset: CGFloat) {
    boxMargin = buttonOffset / 2
    iconPadding = buttonOffset - boxMargin
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
    case .editor: "doc.text"
    case .sidebar: "sidebar.left"
    }
  }
}
