import UniformTypeIdentifiers

extension UTType {
  /// `.novel` 작품 폴더(문서 패키지). 식별자는 App/Info.plist의 UTExportedTypeDeclarations와 같아야 한다.
  static let novelProject = UTType(exportedAs: "com.haapy2.noveleditor.project")
}
