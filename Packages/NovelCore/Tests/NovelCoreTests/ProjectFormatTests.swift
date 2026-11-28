import Testing
@testable import NovelCore

struct ProjectFormatTests {
  @Test func packageExtensionIsNovel() {
    #expect(ProjectFormat.packageExtension == "novel")
  }

  /// 2: episode groups. When bumping, also check the tests reading old formats (EpisodeGroupingTests).
  @Test func schemaVersionIsTwo() {
    #expect(ProjectFormat.currentSchemaVersion == 2)
  }
}
