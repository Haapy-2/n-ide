import AppKit
import SwiftUI

/// Measures the distance (pt) from this view's left edge to the left edge of the window's red close button.
/// Used to align sidebar text and Settings list icons with the close button.
/// Not hard-coded because button and list positions vary with sidebar collapse, full screen and macOS version.
/// Reports nil when the traffic lights aren't visible (full screen etc.).
struct TrafficLightOffsetReader: NSViewRepresentable {
  let onChange: (CGFloat?) -> Void

  /// Convert the measured distance into the row's inner left padding. Shared by the workspace sidebar and the Settings window.
  /// 8 when the buttons aren't visible (full screen). Clamped to 4–40 so it's never too tight or too far.
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

    // Relaid out when an ancestor view moves, e.g. sidebar collapse/expand.
    override func layout() {
      super.layout()
      scheduleMeasure()
    }

    @objc private func windowChanged() { scheduleMeasure() }

    // Measured after layout and reported only when the value changes (to avoid touching SwiftUI state on every layout).
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
