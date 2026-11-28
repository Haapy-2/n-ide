import SwiftUI

/// User-changed shortcuts. Holds only those differing from defaults (so changing a default reaches people who didn't customize it).
/// Stored under UserDefaults key `AppSettingKey.shortcuts` as "command=combo" lines. An empty combo means "no shortcut".
struct ShortcutSettings: Equatable {
  /// A nil value means the user removed the shortcut
  private(set) var overrides: [ShortcutCommand: KeyCombo?] = [:]
  /// "Snapshot on save" enabled (default off). When on, its dedicated key is freed and the save-now / take-snapshot fields lock.
  private(set) var savesWithSnapshot = false

  /// Line in the stored text marking it enabled. Starts with @ so it can't clash with command names.
  private static let savesWithSnapshotLine = "@savesWithSnapshot"

  init() {}

  init(storageText: String) {
    for line in storageText.split(separator: "\n") {
      if line == Self.savesWithSnapshotLine {
        savesWithSnapshot = true
        continue
      }
      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let command = ShortcutCommand(rawValue: String(parts[0])) else { continue }
      let comboText = parts.count > 1 ? String(parts[1]) : ""
      if comboText.isEmpty {
        overrides[command] = .some(nil)
      } else if let combo = KeyCombo(storageText: comboText) {
        overrides[command] = .some(combo)
      }
    }
  }

  var storageText: String {
    let lines = ShortcutCommand.allCases.compactMap { command -> String? in
      guard let combo = overrides[command] else { return nil }
      return "\(command.rawValue)=\(combo?.storageText ?? "")"
    }
    return (lines + (savesWithSnapshot ? [Self.savesWithSnapshotLine] : [])).joined(separator: "\n")
  }

  // MARK: - Reading

  func combo(for command: ShortcutCommand) -> KeyCombo? {
    if let override = overrides[command] { return override }
    return command.defaultCombo
  }

  /// Shortcut to attach to the menu item. nil if none (no shortcut shown in the menu).
  func shortcut(_ command: ShortcutCommand) -> KeyboardShortcut? {
    combo(for: command)?.keyboardShortcut
  }

  func isCustomized(_ command: ShortcutCommand) -> Bool {
    overrides[command] != nil
  }

  var hasCustomizations: Bool { !overrides.isEmpty || savesWithSnapshot }

  /// Whether this key is actually active. Save now and snapshot on save are mutually exclusive (same menu item).
  func isActive(_ command: ShortcutCommand) -> Bool {
    switch command {
    case .saveNow: !savesWithSnapshot
    case .saveWithSnapshot: savesWithSnapshot
    default: true
    }
  }

  /// Fields whose key can't be changed in Settings (no recording, no defaults button).
  func isLocked(_ command: ShortcutCommand) -> Bool {
    switch command {
    case .saveNow, .takeSnapshot: savesWithSnapshot
    case .saveWithSnapshot: !savesWithSnapshot
    default: false
    }
  }

  /// Shortcut of the File menu "save now" item. When enabled it uses the snapshot-on-save key.
  var saveMenuShortcut: KeyboardShortcut? {
    shortcut(savesWithSnapshot ? .saveWithSnapshot : .saveNow)
  }

  // MARK: - Checking before choosing

  enum Problem: Equatable {
    /// No ⌘ (letter-only combos would block writing)
    case needsCommand
    /// Standard system/editing shortcut. Shown with the reason (what uses it)
    case reserved(String)
    /// Another app command already uses it
    case usedBy(ShortcutCommand)
    /// Used by a locked field, so it can't be taken
    case usedByLocked(ShortcutCommand)
  }

  /// Overlapping with the inactive one (save now ↔ snapshot on save) is fine. Same menu item, never active at once.
  func problem(with combo: KeyCombo, for command: ShortcutCommand) -> Problem? {
    guard combo.modifiers.contains(.command) else { return .needsCommand }
    if let owner = Self.reserved[combo] { return .reserved(owner) }
    let others = ShortcutCommand.allCases.filter { $0 != command && isActive($0) && !Self.areAlternatives($0, command) }
    if let other = others.first(where: { self.combo(for: $0) == combo }) {
      return isLocked(other) ? .usedByLocked(other) : .usedBy(other)
    }
    return nil
  }

  private static func areAlternatives(_ a: ShortcutCommand, _ b: ShortcutCommand) -> Bool {
    Set([a, b]) == [.saveNow, .saveWithSnapshot]
  }

  // MARK: - Changing

  /// If equal to the default, remove the override. Call after checking `problem`.
  mutating func set(_ combo: KeyCombo?, for command: ShortcutCommand) {
    overrides[command] = combo == command.defaultCombo ? nil : .some(combo)
  }

  /// Take a combo another command was using. That command loses its shortcut.
  mutating func take(_ combo: KeyCombo, for command: ShortcutCommand, from other: ShortcutCommand) {
    set(nil, for: other)
    set(combo, for: command)
  }

  mutating func reset(_ command: ShortcutCommand) {
    overrides[command] = nil
  }

  mutating func resetAll() {
    overrides = [:]
    savesWithSnapshot = false
  }

  /// Toggle. If the newly active side's key went to another command meanwhile, clear it (so two items don't respond to one key).
  mutating func setSavesWithSnapshot(_ on: Bool) {
    guard on != savesWithSnapshot else { return }
    savesWithSnapshot = on
    let active: ShortcutCommand = on ? .saveWithSnapshot : .saveNow
    if let combo = combo(for: active), problem(with: combo, for: active) != nil {
      set(nil, for: active)
    }
  }

  // MARK: - Combos that can't be chosen

  /// Standard shortcuts used by the system and the editor → who uses them
  static let reserved: [KeyCombo: String] = {
    var table: [KeyCombo: String] = [
      KeyCombo("q", [.command]): "앱 종료",
      KeyCombo("w", [.command]): "창 닫기",
      KeyCombo("w", [.command, .option]): "모두 닫기",
      KeyCombo("h", [.command]): "앱 가리기",
      KeyCombo("h", [.command, .option]): "기타 가리기",
      KeyCombo("m", [.command]): "창 최소화",
      KeyCombo(",", [.command]): "설정",
      KeyCombo("/", [.command, .shift]): "도움말",
      KeyCombo("`", [.command]): "다음 창",
      KeyCombo("c", [.command]): "복사",
      KeyCombo("v", [.command]): "붙여넣기",
      KeyCombo("x", [.command]): "오려두기",
      KeyCombo("a", [.command]): "전체 선택",
      KeyCombo("z", [.command]): "실행 취소",
      KeyCombo("z", [.command, .shift]): "실행 복귀",
      KeyCombo("s", [.command, .option]): "사이드바 보기·숨기기",
      KeyCombo(.space, [.command]): "Spotlight",
      KeyCombo(.space, [.command, .control]): "이모지 및 기호",
      KeyCombo(.tab, [.command]): "앱 전환",
      KeyCombo(.delete, [.command]): "줄 앞까지 지우기",
    ]
    // Caret movement/selection (editor)
    for arrow in [KeyCombo.Key.upArrow, .downArrow, .leftArrow, .rightArrow] {
      table[KeyCombo(arrow, [.command])] = "커서 이동"
      table[KeyCombo(arrow, [.command, .shift])] = "선택 넓히기"
    }
    return table
  }()
}
