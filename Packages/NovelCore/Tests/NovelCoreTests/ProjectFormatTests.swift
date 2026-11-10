import Testing
@testable import NovelCore

struct ProjectFormatTests {
  @Test func packageExtensionIsNovel() {
    #expect(ProjectFormat.packageExtension == "novel")
  }

  @Test func schemaVersionStartsAtOne() {
    #expect(ProjectFormat.currentSchemaVersion == 1)
  }
}
