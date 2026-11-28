import Foundation

/// Format info for the project folder (`.novel` package). Kept in one place so the app and NovelCore use the same values.
public enum ProjectFormat {
  /// Project folder extension. Registered as a document package in Finder.
  public static let packageExtension = "novel"
  /// Current `project.json` format version. Bump it when the format changes, together with migration code for old versions.
  /// 2: added episode groups (`groups`, episode `group`). 1 reads as having no groups.
  /// An old app opening 2 would save without knowing groups and drop them, so the version was bumped to make old apps reject 2.
  public static let currentSchemaVersion = 2
}
