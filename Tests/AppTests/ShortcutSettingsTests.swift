import XCTest
@testable import NovelEditor

/// 단축키 표와 사용자가 바꾼 단축키(PLAN.md 12장).
@MainActor
final class ShortcutSettingsTests: XCTestCase {
  func testDefaultsHaveNoClashes() {
    let combos = ShortcutCommand.allCases.compactMap(\.defaultCombo)
    XCTAssertEqual(Set(combos).count, combos.count, "기본 단축키끼리 겹친다")
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
}
