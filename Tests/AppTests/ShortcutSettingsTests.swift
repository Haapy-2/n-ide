import XCTest
@testable import NovelEditor

@MainActor
final class ShortcutSettingsTests: XCTestCase {
  /// 지금 저장과 저장하면서 스냅샷 찍기는 같은 ⌘S지만 동시에 쓰이지 않으므로(isActive) 쓰이는 명령끼리만 본다.
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
    // 자기 자신이 쓰는 조합은 문제없다
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .saveNow))
  }

  func testTakeClearsPreviousOwner() {
    var settings = ShortcutSettings()
    settings.take(KeyCombo("n", [.command]), for: .saveNow, from: .newEpisode)
    XCTAssertEqual(settings.combo(for: .saveNow), KeyCombo("n", [.command]))
    XCTAssertNil(settings.combo(for: .newEpisode))
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .takeSnapshot))
  }

  /// 한글 입력 중에도 키 위치로 읽어서 S 자리는 "s"다.
  func testKeyCodes() {
    XCTAssertEqual(KeyCombo.key(forKeyCode: 1), .character("s"))
    XCTAssertEqual(KeyCombo.key(forKeyCode: 45), .character("n"))
    XCTAssertEqual(KeyCombo.key(forKeyCode: 126), .upArrow)
    XCTAssertEqual(KeyCombo.key(forKeyCode: 51), .delete)
    XCTAssertNil(KeyCombo.key(forKeyCode: 122), "F1 같은 기능 키는 받지 않는다")
  }

  // MARK: - 저장하면서 스냅샷 찍기

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
    // 지금 저장은 쓰이지 않아 ⌘S를 그대로 써도 된다
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .saveWithSnapshot))
    // 잠긴 스냅샷 찍기의 키는 가져올 수 없다
    XCTAssertEqual(settings.problem(with: KeyCombo("s", [.command, .control]), for: .saveWithSnapshot), .usedByLocked(.takeSnapshot))
    XCTAssertEqual(settings.problem(with: KeyCombo("n", [.command]), for: .saveWithSnapshot), .usedBy(.newEpisode))
    // 꺼져 있으면 전용 키는 다른 명령과 부딪치지 않는다
    settings.setSavesWithSnapshot(false)
    XCTAssertNil(settings.problem(with: KeyCombo("s", [.command]), for: .saveNow))
  }

  /// 켜 있는 동안 ⌘S를 다른 명령이 가져갔다면, 끌 때 지금 저장의 키를 비워 같은 키 두 개가 듣지 않게 한다.
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
