import SwiftUI

/// 회차 메뉴가 지금 앞에 있는 작업 공간 창에 보내는 명령. 할 수 없는 명령은 nil(메뉴에서 흐리게).
struct WorkspaceActions {
  var addEpisode: () -> Void
  var renameSelected: (() -> Void)?
  var trashSelected: (() -> Void)?
  /// 여러 회차를 고른 채일 때 휴지통 메뉴 이름("지금 회차(3화)만 휴지통으로 이동…"). 평소에는 nil.
  var trashTitle: String? = nil
  var setGoalSelected: (() -> Void)?
  var selectPrevious: (() -> Void)?
  var selectNext: (() -> Void)?
  /// 기다리지 않고 지금 저장(⌘S). 자동 저장이 이미 하는 일을 앞당길 뿐이다.
  var saveNow: (() -> Void)?
  /// 저장하고 이어서 스냅샷(설정 → 단축키에서 켰을 때 지금 저장 대신). 글이 마지막 스냅샷과 같으면 스냅샷은 건너뛴다.
  var saveWithSnapshot: (() -> Void)?
  var takeSnapshot: (() -> Void)?
  var showSnapshots: (() -> Void)?
  /// 사이드바 자리에 작품 전체 검색 패널을 연다(⇧⌘F). 이미 열려 있으면 입력 칸에 초점을 준다.
  var showSearch: (() -> Void)?
  /// 가장 최근 전체 바꾸기의 되돌리기 창을 연다. 되돌릴 바꾸기가 없으면 nil.
  var revertReplace: (() -> Void)?
  /// 고른 회차들(없으면 지금 회차)을 묶는다. 이름을 묻는 창이 뜬다.
  var groupMarked: (() -> Void)?
  /// 지금 회차가 든 묶음을 푼다. 묶음 밖이면 nil.
  var ungroupSelected: (() -> Void)?
}

extension FocusedValues {
  @Entry var workspaceActions: WorkspaceActions?
  /// 사이드바(회차 목록)가 키보드 초점을 갖고 있는지. 회차 메뉴가 단축키를 바꾸는 데 쓴다.
  @Entry var episodeSidebarFocused: Bool?
}
