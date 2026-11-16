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
  /// 지금 회차 스냅샷 찍기(⌃⌘S)
  var takeSnapshot: (() -> Void)?
  /// 지금 회차 스냅샷 판 열기(⇧⌘S)
  var showSnapshots: (() -> Void)?
}

extension FocusedValues {
  @Entry var workspaceActions: WorkspaceActions?
  /// 사이드바(회차 목록)가 키보드 초점을 갖고 있는지. 회차 메뉴가 단축키를 바꾸는 데 쓴다.
  @Entry var episodeSidebarFocused: Bool?
}
