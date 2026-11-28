import AppKit

/// Color tokens used by the editor (AppKit). Values are in Resources/Colors.xcassets.
extension NSColor {
  static let paper = NSColor(named: "paper")!
  static let ink = NSColor(named: "ink")!
  static let inkMuted = NSColor(named: "inkMuted")!
  static let accentToken = NSColor(named: "accent")!
  static let ruleToken = NSColor(named: "rule")!

  /// Selection: accent at 18% light, 28% dark (DESIGN.md ch.1).
  static let selectionToken = NSColor(name: nil) { appearance in
    let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return NSColor(named: "accent")!.withAlphaComponent(dark ? 0.28 : 0.18)
  }
}
