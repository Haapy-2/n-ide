import Testing
@testable import NovelCore

struct ProjectFormatTests {
  @Test func packageExtensionIsNovel() {
    #expect(ProjectFormat.packageExtension == "novel")
  }

  /// 2(2026-11-20): 회차 묶음. 올리면 옛 형식을 읽는 테스트(EpisodeGroupingTests)도 함께 본다.
  @Test func schemaVersionIsTwo() {
    #expect(ProjectFormat.currentSchemaVersion == 2)
  }
}
