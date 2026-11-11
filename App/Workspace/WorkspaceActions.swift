import SwiftUI

/// 회차 메뉴가 지금 앞에 있는 작업 공간 창에 보내는 명령. 할 수 없는 명령은 nil(메뉴에서 흐리게).
struct WorkspaceActions {
  var addEpisode: () -> Void
  var renameSelected: (() -> Void)?
  var trashSelected: (() -> Void)?
  var selectPrevious: (() -> Void)?
  var selectNext: (() -> Void)?
}

extension FocusedValues {
  @Entry var workspaceActions: WorkspaceActions?
}
