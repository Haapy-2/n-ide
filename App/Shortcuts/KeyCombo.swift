import SwiftUI

/// One shortcut: key + modifiers. Stored in settings as a string like "ctrl+cmd+s".
struct KeyCombo: Hashable, Sendable {
  enum Key: Hashable, Sendable {
    /// One lowercase letter, digit or symbol
    case character(Character)
    case upArrow, downArrow, leftArrow, rightArrow, delete, returnKey, escape, tab, space
  }

  struct Modifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let control = Modifiers(rawValue: 1)
    static let option = Modifiers(rawValue: 2)
    static let shift = Modifiers(rawValue: 4)
    static let command = Modifiers(rawValue: 8)
  }

  var key: Key
  var modifiers: Modifiers

  init(_ key: Key, _ modifiers: Modifiers) {
    self.key = key
    self.modifiers = modifiers
  }

  init(_ character: Character, _ modifiers: Modifiers) {
    self.init(.character(character), modifiers)
  }

  // MARK: - Attaching to menus

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
  }

  private var keyEquivalent: KeyEquivalent {
    switch key {
    case .character(let character): KeyEquivalent(character)
    case .upArrow: .upArrow
    case .downArrow: .downArrow
    case .leftArrow: .leftArrow
    case .rightArrow: .rightArrow
    case .delete: .delete
    case .returnKey: .return
    case .escape: .escape
    case .tab: .tab
    case .space: .space
    }
  }

  private var eventModifiers: EventModifiers {
    var result: EventModifiers = []
    if modifiers.contains(.control) { result.insert(.control) }
    if modifiers.contains(.option) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    if modifiers.contains(.command) { result.insert(.command) }
    return result
  }

  // MARK: - Display (same order as menus: ⌃⌥⇧⌘)

  var displayText: String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    switch key {
    case .character(let character): text += character.uppercased()
    case .upArrow: text += "↑"
    case .downArrow: text += "↓"
    case .leftArrow: text += "←"
    case .rightArrow: text += "→"
    case .delete: text += "⌫"
    case .returnKey: text += "↩"
    case .escape: text += "⎋"
    case .tab: text += "⇥"
    case .space: text += "Space"
    }
    return text
  }

  // MARK: - Storage string

  private static let modifierNames: [(Modifiers, String)] = [
    (.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd"),
  ]
  private static let keyNames: [Key: String] = [
    .upArrow: "up", .downArrow: "down", .leftArrow: "left", .rightArrow: "right", .delete: "delete",
    .returnKey: "return", .escape: "escape", .tab: "tab", .space: "space", .character("+"): "plus",
  ]

  var storageText: String {
    let names = Self.modifierNames.filter { modifiers.contains($0.0) }.map(\.1)
    let keyName: String
    if let name = Self.keyNames[key] {
      keyName = name
    } else if case .character(let character) = key {
      keyName = String(character)
    } else {
      keyName = ""
    }
    return (names + [keyName]).joined(separator: "+")
  }

  init?(storageText: String) {
    let parts = storageText.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let keyName = parts.last, !keyName.isEmpty else { return nil }
    var modifiers: Modifiers = []
    for name in parts.dropLast() {
      guard let modifier = Self.modifierNames.first(where: { $0.1 == name })?.0 else { return nil }
      modifiers.insert(modifier)
    }
    if let key = Self.keyNames.first(where: { $0.value == keyName })?.key {
      self.init(key, modifiers)
    } else if keyName.count == 1, let character = keyName.first {
      self.init(.character(character), modifiers)
    } else {
      return nil
    }
  }

  // MARK: - Key code → key

  /// Keys are identified by keyboard position (virtual key code, US layout).
  /// Reading characters would give "ㄴ" at the S position during Hangul input, so use the input-source-independent key position.
  static func key(forKeyCode code: UInt16) -> Key? {
    if let character = characterKeyCodes[code] { return .character(character) }
    switch code {
    case 36: return .returnKey
    case 48: return .tab
    case 49: return .space
    case 51: return .delete
    case 53: return .escape
    case 123: return .leftArrow
    case 124: return .rightArrow
    case 125: return .downArrow
    case 126: return .upArrow
    default: return nil
    }
  }

  private static let characterKeyCodes: [UInt16: Character] = [
    0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
    12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4",
    22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o",
    32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
    43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`",
  ]
}
