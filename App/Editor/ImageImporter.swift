import AppKit
import ImageIO
import NovelCore
import UniformTypeIdentifiers

/// Where an image to insert comes from: a file (open panel, Finder drop, copied file) or picture data (copied image, screenshot).
nonisolated enum ImageSource: Sendable {
  case file(URL)
  case data(Data)

  var originalName: String {
    switch self {
    case .file(let url): url.lastPathComponent
    case .data: ""
    }
  }
}

/// Turns an image source into a file in the project's `images/` (PLAN ch.19 #1, G16). PNG, JPEG and HEIC are copied byte for byte;
/// anything else ImageIO reads (PSD, WebP, TIFF, BMP, the first frame of a GIF) is written as PNG. Runs off the main thread.
enum ImageImporter {
  nonisolated struct Imported: Sendable {
    let fileName: String
    let meta: ImageMeta
  }

  nonisolated enum Failure: Error {
    /// Not an image ImageIO can read, or an iCloud file not downloaded yet.
    case unreadable
    case writeFailed(String)
  }

  nonisolated static func write(_ source: ImageSource, to store: ProjectStore) throws(Failure) -> Imported {
    let data: Data
    switch source {
    case .file(let url):
      guard let contents = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw .unreadable }
      data = contents
    case .data(let contents):
      data = contents
    }
    let (bytes, fileExtension) = try storable(data)
    do {
      let fileName = try store.addImage(bytes, fileExtension: fileExtension)
      let meta = ImageMeta(id: ImageID(fileName: fileName), name: ImageMeta.name(fromOriginalFileName: source.originalName))
      return Imported(fileName: fileName, meta: meta)
    } catch let error as ProjectError {
      throw .writeFailed(error.userMessage)
    } catch {
      throw .writeFailed(error.localizedDescription)
    }
  }

  nonisolated private static func storable(_ data: Data) throws(Failure) -> (Data, String) {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) > 0,
      let type = CGImageSourceGetType(source) as String?,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      properties[kCGImagePropertyPixelWidth] != nil
    else { throw .unreadable }
    if let kept = ImageImport.storedExtension(forTypeIdentifier: type) { return (data, kept) }
    let output = NSMutableData()
    // Copying from the source keeps metadata such as EXIF orientation, so the PNG shows the same way up.
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
      throw .unreadable
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, nil)
    guard CGImageDestinationFinalize(destination) else { throw .unreadable }
    return (output as Data, "png")
  }

  // MARK: - Pasteboard

  /// Picture data types the editor accepts besides files.
  static let pictureTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

  /// Images on a pasteboard, or nil when it should paste or drop as text. Files win over picture data, because Finder puts the
  /// file's icon next to the file. Picture data counts only without text: apps that copy text often add a rendered picture of it.
  static func sources(on pasteboard: NSPasteboard) -> [ImageSource]? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
      let images = urls.filter(isImageFile)
      return images.isEmpty ? nil : images.map(ImageSource.file)
    }
    guard pasteboard.string(forType: .string) == nil else { return nil }
    for type in pictureTypes {
      if let data = pasteboard.data(forType: type) { return [.data(data)] }
    }
    return nil
  }

  static func isImageFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) == true
  }
}
