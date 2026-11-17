import SwiftUI

/// 사용자가 바꾼 단축키. 기본값과 다른 것만 담는다(기본값을 고치면 바꾸지 않은 사람에게도 바로 반영되게).
/// UserDefaults 키 `AppSettingKey.shortcuts`에 "명령=조합" 줄로 저장한다. 조합이 비어 있으면 "단축키 없음".
struct ShortcutSettings: Equatable {
  /// 값이 nil이면 사용자가 단축키를 없앤 것
  private(set) var overrides: [ShortcutCommand: KeyCombo?] = [:]
  /// "저장하면서 스냅샷 찍기" 켜짐(기본 끔). 켜면 그 전용 키가 풀리고 지금 저장·스냅샷 찍기 칸이 잠긴다.
  private(set) var savesWithSnapshot = false

  /// 저장 글에서 켜짐을 나타내는 줄. 명령 이름과 겹치지 않게 @로 시작한다.
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

  // MARK: - 읽기

  func combo(for command: ShortcutCommand) -> KeyCombo? {
    if let override = overrides[command] { return override }
    return command.defaultCombo
  }

  /// 메뉴 항목에 붙일 단축키. 없으면 nil(메뉴에 단축키가 안 보인다).
  func shortcut(_ command: ShortcutCommand) -> KeyboardShortcut? {
    combo(for: command)?.keyboardShortcut
  }

  func isCustomized(_ command: ShortcutCommand) -> Bool {
    overrides[command] != nil
  }

  var hasCustomizations: Bool { !overrides.isEmpty || savesWithSnapshot }

  /// 지금 키가 실제로 듣는 명령인지. 지금 저장과 저장하면서 스냅샷 찍기는 둘 중 하나만 쓰인다(같은 메뉴 항목).
  func isActive(_ command: ShortcutCommand) -> Bool {
    switch command {
    case .saveNow: !savesWithSnapshot
    case .saveWithSnapshot: savesWithSnapshot
    default: true
    }
  }

  /// 설정 창에서 키를 바꿀 수 없는 칸(녹화도, 기본값 버튼도 없음).
  func isLocked(_ command: ShortcutCommand) -> Bool {
    switch command {
    case .saveNow, .takeSnapshot: savesWithSnapshot
    case .saveWithSnapshot: !savesWithSnapshot
    default: false
    }
  }

  /// 파일 메뉴 "지금 저장" 항목의 단축키. 켜져 있으면 저장하면서 스냅샷 찍기의 키를 쓴다.
  var saveMenuShortcut: KeyboardShortcut? {
    shortcut(savesWithSnapshot ? .saveWithSnapshot : .saveNow)
  }

  // MARK: - 고르기 전에 보기

  enum Problem: Equatable {
    /// ⌘가 없다(글자만 누르는 조합은 글쓰기를 막는다)
    case needsCommand
    /// 시스템·편집 표준 단축키. 이유(무엇이 쓰는지)를 함께 보여 준다
    case reserved(String)
    /// 다른 앱 명령이 이미 쓰고 있다
    case usedBy(ShortcutCommand)
    /// 잠긴 칸이 쓰고 있어 가져올 수 없다
    case usedByLocked(ShortcutCommand)
  }

  /// 쓰이지 않는 쪽(지금 저장 ↔ 저장하면서 스냅샷 찍기)과는 겹쳐도 괜찮다. 같은 메뉴 항목이라 동시에 듣지 않는다.
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

  // MARK: - 바꾸기

  /// 기본값과 같으면 바꾼 기록을 지운다. `problem`을 먼저 확인하고 부른다.
  mutating func set(_ combo: KeyCombo?, for command: ShortcutCommand) {
    overrides[command] = combo == command.defaultCombo ? nil : .some(combo)
  }

  /// 다른 명령이 쓰던 조합을 가져온다. 그 명령은 단축키가 빈다.
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

  /// 켜고 끈다. 새로 쓰이게 된 쪽의 키가 그사이 다른 명령에 가 있으면 그 키는 비운다(같은 키 두 개가 듣지 않게).
  mutating func setSavesWithSnapshot(_ on: Bool) {
    guard on != savesWithSnapshot else { return }
    savesWithSnapshot = on
    let active: ShortcutCommand = on ? .saveWithSnapshot : .saveNow
    if let combo = combo(for: active), problem(with: combo, for: active) != nil {
      set(nil, for: active)
    }
  }

  // MARK: - 고를 수 없는 조합

  /// 시스템과 편집기가 쓰는 표준 단축키 → 쓰는 곳
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
    // 커서 이동·선택(편집기)
    for arrow in [KeyCombo.Key.upArrow, .downArrow, .leftArrow, .rightArrow] {
      table[KeyCombo(arrow, [.command])] = "커서 이동"
      table[KeyCombo(arrow, [.command, .shift])] = "선택 넓히기"
    }
    return table
  }()
}
