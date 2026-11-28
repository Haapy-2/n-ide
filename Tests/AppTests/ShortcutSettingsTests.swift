import XCTest
@testable import NovelEditor

@MainActor
final class ShortcutSettingsTests: XCTestCase {
  /// Save now and snapshot on save share ⌘S but are never active at once (isActive), so only active commands are compared.
  func testDefaultsHaveNoClashes() {
    for savesWithSnapshot in [false, true] {
      var settings = ShortcutSettings()
      settings.setSavesWithSnapshot(savesWithSnapshot)
      let combos = ShortcutCommand.allCases.filter(settings.isActive).compactMap(\.defaultCombo)
      XCTAssertEqual(Set(combos).count, combos.count, "기본 단축키끼리 겹친다")
      XCTAssertEqual(settings.combo(for: .saveWithSnapshot), KeyCombo("s", [.command]), "켜고 끌 때 기본 키가 비지 않는다")
    }
    for command in ShortcutCommand.allCases {
      guard let combo = command.defaultCombo else { continue }
      XCTAssertNil(ShortcutSettings().problem(with: combo, for: command), command.title)
    }
  }

  func testStorageRoundTrip() {
    var settings = ShortcutSettings()
    settings.set(KeyCombo("j", [.command, .control]), for: .saveNow)
    settings.set(nil, for: .newEpisode)
    settings.set(KeyCombo("+", [.command, .option, .shift]), for: .episodeGoal)
    settings.set(KeyCombo(.upArrow, [.command, .control]), for: .previousEpisode)
    let restored = ShortcutSettings(storageText: settings.storageText)
    XCTAssertEqual(restored, settings)
    XCTAssertEqual(restored.combo(for: .saveNow), KeyCombo("j", [.command, .control]))
    XCTAssertNil(restored.combo(for: .newEpisode))
    XCTAssertTrue(restored.isCustomized(.newEpisode))
    XCTAssertEqual(restored.combo(for: .episodeGoal)?.displayText, "⌥⇧⌘+")
    XCTAssertEqual(restored.combo(for: .takeSnapshot), ShortcutCommand.takeSnapshot.defaultCombo)
  }

  func testBrokenStorageIsIgnored() {
    let settings = ShortcutSettings(storageText: "없는명령=cmd+j\nsaveNow=cmd+이상한키\nshowSnapshots=meta+s")
    XCTAssertFalse(settings.hasCustomizations)
  }

  func testSettingDefaultRemovesOverride() {
    var settings = ShortcutSettings()
    settings.set(KeyCombo("j", [.command]), for: .saveNow)
    settings.set(ShortcutCommand.saveNow.defaultCombo, for: .saveNow)
    XCTAssertFalse(settings.isCustomized(.saveNow))
    XCTAssertEqual(settings.storageText, "")
  }

  func testProblems() {
    let settings = ShortcutSettings()
    XCTAssertEqual(settings.problem(with: KeyCombo("j", [.control]), for: .saveNow), .needsCommand)
    XCTAssertEqual(settings.problem(with: KeyCombo("q", [.command]), for: .saveNow), .reserved("앱 종료"))
    XCTAssertEqual(settings.problem(with: KeyCombo("s", [.command, .option]), for: .takeSnapshot), .reserved("사이드바 보기·숨기기"))
    XCTAssertEqual(settings.problem(with: KeyCombo("n", [.command]), for: .saveNow), .usedBy(.newEpisode))
    // A combo used by the command itself is fine
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .saveNow))
  }

  func testTakeClearsPreviousOwner() {
    var settings = ShortcutSettings()
    settings.take(KeyCombo("n", [.command]), for: .saveNow, from: .newEpisode)
    XCTAssertEqual(settings.combo(for: .saveNow), KeyCombo("n", [.command]))
    XCTAssertNil(settings.combo(for: .newEpisode))
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .takeSnapshot))
  }

  /// Read by key position even during Hangul input, so the S position is "s".
  func testKeyCodes() {
    XCTAssertEqual(KeyCombo.key(forKeyCode: 1), .character("s"))
    XCTAssertEqual(KeyCombo.key(forKeyCode: 45), .character("n"))
    XCTAssertEqual(KeyCombo.key(forKeyCode: 126), .upArrow)
    XCTAssertEqual(KeyCombo.key(forKeyCode: 51), .delete)
    XCTAssertNil(KeyCombo.key(forKeyCode: 122), "F1 같은 기능 키는 받지 않는다")
  }

  // MARK: - Snapshot on save

  func testLockedCellsFollowToggle() {
    var settings = ShortcutSettings()
    XCTAssertFalse(settings.savesWithSnapshot, "기본은 끔")
    XCTAssertTrue(settings.isLocked(.saveWithSnapshot))
    XCTAssertFalse(settings.isLocked(.saveNow))
    XCTAssertFalse(settings.isLocked(.takeSnapshot))
    settings.setSavesWithSnapshot(true)
    XCTAssertFalse(settings.isLocked(.saveWithSnapshot))
    XCTAssertTrue(settings.isLocked(.saveNow))
    XCTAssertTrue(settings.isLocked(.takeSnapshot))
    XCTAssertFalse(settings.isLocked(.showSnapshots), "다른 칸은 그대로")
    XCTAssertEqual(settings.saveMenuShortcut, settings.shortcut(.saveWithSnapshot))
  }

  func testToggleSurvivesStorageAndResetAll() {
    var settings = ShortcutSettings()
    settings.setSavesWithSnapshot(true)
    settings.set(KeyCombo("k", [.command, .control]), for: .saveWithSnapshot)
    let restored = ShortcutSettings(storageText: settings.storageText)
    XCTAssertEqual(restored, settings)
    XCTAssertTrue(restored.savesWithSnapshot)
    XCTAssertTrue(restored.hasCustomizations)
    var reset = restored
    reset.resetAll()
    XCTAssertEqual(reset, ShortcutSettings())
  }

  func testSaveWithSnapshotProblems() {
    var settings = ShortcutSettings()
    settings.setSavesWithSnapshot(true)
    // Save now is inactive, so ⌘S can be used as is
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .saveWithSnapshot))
    // The locked take-snapshot key can't be taken
    XCTAssertEqual(settings.problem(with: KeyCombo("s", [.command, .control]), for: .saveWithSnapshot), .usedByLocked(.takeSnapshot))
    XCTAssertEqual(settings.problem(with: KeyCombo("n", [.command]), for: .saveWithSnapshot), .usedBy(.newEpisode))
    // When off, the dedicated key doesn't clash with other commands
    settings.setSavesWithSnapshot(false)
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .saveNow))
  }

  /// If another command took ⌘S while it was on, turning it off clears save now's key so two items don't respond to one key.
  func testToggleClearsClashingKey() {
    var settings = ShortcutSettings()
    settings.setSavesWithSnapshot(true)
    settings.set(KeyCombo("k", [.command, .control]), for: .saveWithSnapshot)
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .showSnapshots))
    settings.set(KeyCombo("s", [.command]), for: .showSnapshots)
    settings.setSavesWithSnapshot(false)
    XCTAssertNil(settings.combo(for: .saveNow))
    XCTAssertEqual(settings.combo(for: .showSnapshots), KeyCombo("s", [.command]))
  }
}
