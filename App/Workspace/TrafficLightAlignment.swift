import AppKit
import SwiftUI

/// 이 뷰의 왼쪽 끝에서 창의 빨간 닫기 버튼 왼쪽 끝까지의 거리(pt)를 잰다.
/// 사이드바 글자와 설정 창 목록 아이콘을 닫기 버튼과 같은 선에 세우려고 쓴다(2026-11-12 사용자 요청).
/// 숫자를 박아 두지 않는 이유: 사이드바 접기·전체 화면·macOS 버전에 따라 버튼과 목록의 위치가 달라진다.
/// 신호등 버튼이 안 보이면(전체 화면 등) nil을 알린다.
struct TrafficLightOffsetReader: NSViewRepresentable {
  let onChange: (CGFloat?) -> Void

  /// 잰 거리를 줄 안쪽 왼쪽 여백으로 바꾼다. 작업 공간 사이드바와 설정 창이 같이 쓴다.
  /// 버튼이 안 보이면(전체 화면) 8. 너무 붙거나 멀어지지 않게 4~40으로 묶는다.
  static func contentInset(for offset: CGFloat?) -> CGFloat {
    guard let offset else { return 8 }
    return min(max(offset, 4), 40)
  }

  func makeNSView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.onChange = onChange
    return view
  }

  func updateNSView(_ nsView: ProbeView, context: Context) {
    nsView.onChange = onChange
  }

  final class ProbeView: NSView {
    var onChange: ((CGFloat?) -> Void)?
    private var lastValue: CGFloat?? = .none

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      NotificationCenter.default.removeObserver(self)
      guard let window else { return }
      let names: [Notification.Name] = [
        NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
        NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification,
      ]
      for name in names {
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
      }
      scheduleMeasure()
    }

    // 사이드바를 접었다 펴는 등 조상 뷰가 움직이면 다시 배치된다.
    override func layout() {
      super.layout()
      scheduleMeasure()
    }

    @objc private func windowChanged() { scheduleMeasure() }

    // 배치가 끝난 뒤에 재고, 값이 바뀔 때만 알린다(SwiftUI 상태를 매 배치마다 건드리지 않으려고).
    private func scheduleMeasure() {
      DispatchQueue.main.async { [weak self] in self?.measure() }
    }

    private func measure() {
      let value = currentOffset()
      if let lastValue, lastValue == value { return }
      lastValue = .some(value)
      onChange?(value)
    }

    private func currentOffset() -> CGFloat? {
      guard let window, !window.styleMask.contains(.fullScreen),
        let button = window.standardWindowButton(.closeButton),
        !button.isHidden, button.window === window
      else { return nil }
      let buttonX = button.convert(button.bounds, to: nil).minX
      let selfX = convert(bounds, to: nil).minX
      return buttonX - selfX
    }
  }
}
