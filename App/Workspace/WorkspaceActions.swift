import SwiftUI

/// 회차 메뉴가 지금 앞에 있는 작업 공간 창에 보내는 명령. 할 수 없는 명령은 nil(메뉴에서 흐리게).
struct WorkspaceActions {
  var addEpisode: () -> Void
  var renameSelected: (() -> Void)?
  var trashSelected: (() -> Void)?
  var setGoalSelected: (() -> Void)?
  var selectPrevious: (() -> Void)?
  var selectNext: (() -> Void)?
  /// 기다리지 않고 지금 저장(⌘S). 자동 저장이 이미 하는 일을 앞당길 뿐이다.
  var saveNow: (() -> Void)?
  /// 저장하고 이어서 스냅샷(설정 → 단축키에서 켰을 때 지금 저장 대신). 글이 마지막 스냅샷과 같으면 스냅샷은 건너뛴다.
  var saveWithSnapshot: (() -> Void)?
  /// 지금 회차 스냅샷 찍기(⌃⌘S)
  var takeSnapshot: (() -> Void)?
  /// 지금 회차 스냅샷 판 열기(⇧⌘S)
  var showSnapshots: (() -> Void)?
  /// 사이드바 자리에 작품 전체 검색 패널을 연다(⇧⌘F). 이미 열려 있으면 입력 칸에 초점을 준다.
  var showSearch: (() -> Void)?
}

extension FocusedValues {
  @Entry var workspaceActions: WorkspaceActions?
  /// 사이드바(회차 목록)가 키보드 초점을 갖고 있는지. 회차 메뉴가 단축키를 바꾸는 데 쓴다.
  @Entry var episodeSidebarFocused: Bool?
}
