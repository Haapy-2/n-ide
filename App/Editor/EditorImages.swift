import AppKit
import ImageIO
import NovelCore

/// Image files for the open episode: pixel size from the file header (fixes the line height before the picture loads, G13),
/// and thumbnails decoded off the main thread at display size, never the full original (PLAN ch.19 #4).
/// Cleared on episode switch. Entries remember the file's modification date and size so a file changed outside is re-read (G5).
final class EditorImages {
  enum Status: Equatable {
    case ready(pixelSize: CGSize)
    case missing
    /// Exists but has no readable header: not downloaded from iCloud yet, or not an image (G17).
    case unreadable
    /// Path outside the project; never read (G4).
    case outside
  }

  /// nil until the editor is attached to a project.
  var project: ProjectLayout? {
    didSet { if project?.root != oldValue?.root { clear() } }
  }
  /// After a thumbnail finished decoding. Argument: the file name.
  var onLoaded: (String) -> Void = { _ in }

  private struct FileStamp: Equatable {
    let modified: Date?
    let size: Int?
  }

  private var statuses: [String: (status: Status, stamp: FileStamp?)] = [:]
  private var thumbnails: [String: (maxPixel: Int, image: NSImage)] = [:]
  private var decoding: Set<String> = []
  /// Bumped on clear so a decode started for an earlier episode doesn't fill the cache.
  private var generation = 0

  func status(of line: ImageLine) -> Status {
    guard case .project(let name) = line.source else { return .outside }
    if let cached = statuses[name] { return cached.status }
    guard let url = project?.imageFile(named: name) else { return .missing }
    let stamp = Self.stamp(of: url)
    let status: Status
    if stamp == nil {
      status = .missing
    } else if let size = Self.pixelSize(of: url) {
      status = .ready(pixelSize: size)
    } else {
      status = .unreadable
    }
    statuses[name] = (status, stamp)
    return status
  }

  /// Thumbnail whose longer side is at least `maxPixel`, or nil while it decodes (`onLoaded` follows).
  func thumbnail(fileName: String, maxPixel: Int) -> NSImage? {
    if let cached = thumbnails[fileName], cached.maxPixel >= maxPixel { return cached.image }
    guard let project, !decoding.contains(fileName) else { return thumbnails[fileName]?.image }
    decoding.insert(fileName)
    let url = project.imageFile(named: fileName)
    let generation = generation
    Task.detached(priority: .userInitiated) {
      let image = Self.decodeThumbnail(url, maxPixel: maxPixel)
      await MainActor.run { [weak self] in
        guard let self, self.generation == generation else { return }
        self.decoding.remove(fileName)
        guard let image else { return }
        self.thumbnails[fileName] = (maxPixel, NSImage(cgImage: image, size: .zero))
        self.onLoaded(fileName)
      }
    }
    return thumbnails[fileName]?.image
  }

  /// Drop entries whose file changed, appeared or vanished since read. Returns the file names dropped.
  @discardableResult
  func revalidate() -> [String] {
    guard let project else { return [] }
    var dropped: [String] = []
    for (name, entry) in statuses where Self.stamp(of: project.imageFile(named: name)) != entry.stamp {
      dropped.append(name)
    }
    for name in dropped {
      statuses[name] = nil
      thumbnails[name] = nil
    }
    return dropped
  }

  func clear() {
    statuses.removeAll()
    thumbnails.removeAll()
    decoding.removeAll()
    generation += 1
  }

  private static func stamp(of url: URL) -> FileStamp? {
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
      values.isRegularFile == true
    else { return nil }
    return FileStamp(modified: values.contentModificationDate, size: values.fileSize)
  }

  /// Size as displayed (EXIF orientation applied), read from the header only.
  private static func pixelSize(of url: URL) -> CGSize? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
      let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
      width > 0, height > 0
    else { return nil }
    let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
    return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  nonisolated private static func decodeThumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
      return nil
    }
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
  }
}
