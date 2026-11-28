import UniformTypeIdentifiers

extension UTType {
  /// `.novel` project folder (document package). The identifier must match UTExportedTypeDeclarations in App/Info.plist.
  static let novelProject = UTType(exportedAs: "com.haapy2.noveleditor.project")
}
