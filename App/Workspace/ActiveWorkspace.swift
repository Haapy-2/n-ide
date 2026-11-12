import Foundation
import Observation

/// 맨 마지막으로 앞에 있던 작업 공간 창의 작품. 설정 창은 어느 작품 창에도 속하지 않아서,
/// 작품별 값(새 회차 목표)을 보여 줄 때 이것을 본다(2026-11-12 사용자 요청).
/// 설정 창이 앞에 오면 작업 공간 창은 뒤로 가지만 값은 그대로 둔다. 작업 공간 창이 닫힐 때만 비운다.
@MainActor
@Observable
final class ActiveWorkspace {
  static let shared = ActiveWorkspace()

  private(set) var model: ProjectModel?
  /// 그 창의 되돌리기 기록. 설정 창에서 바꾼 목표도 작업 공간에서 ⌘Z로 되돌릴 수 있게 같은 기록에 남긴다.
  @ObservationIgnored private(set) weak var undoManager: UndoManager?

  func activate(_ model: ProjectModel, undoManager: UndoManager?) {
    if self.model !== model { self.model = model }
    self.undoManager = undoManager
  }

  func deactivate(_ model: ProjectModel) {
    guard self.model === model else { return }
    self.model = nil
    undoManager = nil
  }
}
