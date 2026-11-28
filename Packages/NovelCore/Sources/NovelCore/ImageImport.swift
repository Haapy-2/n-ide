import Foundation

/// Adding image files to a project and placing their lines (PLAN ch.19 #1, G10·G16). The file is fully written before any
/// manuscript line points at it, and an existing file is never replaced (decision 34).
public enum ImageImport {
  /// Extension for formats stored byte for byte. nil → the app converts to PNG first (PSD, WebP, GIF, TIFF, BMP…).
  public static func storedExtension(forTypeIdentifier type: String) -> String? {
    switch type {
    case "public.png": "png"
    case "public.jpeg": "jpg"
    case "public.heic": "heic"
    default: nil
    }
  }

  /// Text that puts image lines in place of `range`, each on a line of its own, and the caret offset right after the last one.
  /// Adds a newline before when the range starts mid-line and after when it ends mid-line, so neighboring text never joins an image line.
  public static func insertion(fileNames: [String], in text: NSString, replacing range: NSRange) -> (text: String, caret: Int) {
    let lines = fileNames.map(ImageLine.markdown(fileName:)).joined(separator: "\n")
    let before = range.location > 0 && !isLineBreak(text.character(at: range.location - 1)) ? "\n" : ""
    let end = NSMaxRange(range)
    let after = end < text.length && !isLineBreak(text.character(at: end)) ? "\n" : ""
    let caret = range.location + (before as NSString).length + (lines as NSString).length
    return (before + lines + after, caret)
  }

  /// File an outside image line points at, for "작품에 넣기" (G4). nil for web addresses: images are never downloaded.
  /// Relative paths resolve from `episodes/`, where the manuscript file lives. Existence is checked by the caller.
  public static func outsideFile(_ path: String, episodesFolder: URL) -> URL? {
    if let url = URL(string: path), let scheme = url.scheme?.lowercased() {
      return scheme == "file" ? url.standardizedFileURL : nil
    }
    if path.hasPrefix("/") { return URL(filePath: path).standardizedFileURL }
    if path.hasPrefix("~/") { return URL(filePath: (path as NSString).expandingTildeInPath).standardizedFileURL }
    return episodesFolder.appending(path: path).standardizedFileURL
  }

  private static func isLineBreak(_ unit: unichar) -> Bool { unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 }
}

extension ProjectStore {
  /// Write image bytes as `images/<new ID>.<ext>` and return the file name. Recreates `images/` if it was deleted (G16).
  public func addImage(_ data: Data, fileExtension: String) throws -> String {
    do {
      try FileManager.default.createDirectory(at: layout.imagesFolder, withIntermediateDirectories: true)
    } catch {
      throw ProjectError.writeFailed(layout.imagesFolder, reason: error.localizedDescription, problem: WriteProblem(error: error))
    }
    let name = "\(ImageID.make().rawValue).\(fileExtension)"
    try AtomicFile.write(data, to: layout.imageFile(named: name), replacing: false)
    return name
  }
}
