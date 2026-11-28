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
  /// A picture's status changed by itself (an iCloud download finished), so its line height must be laid out again.
  var onStatusChanged: (String) -> Void = { _ in }
  /// Pictures within a screen of the visible area. When a thumbnail arrives, the others are dropped (PLAN ch.19 #4):
  /// a long episode keeps a few decoded pictures, not all of them. Nothing runs per keystroke.
  var nearbyNames: () -> Set<String> = { [] }

  private struct FileStamp: Equatable {
    let modified: Date?
    let size: Int?
  }

  private var statuses: [String: (status: Status, stamp: FileStamp?)] = [:]
  private var thumbnails: [String: (maxPixel: Int, image: NSImage)] = [:]
  private var decoding: Set<String> = []
  private var downloading: Set<String> = []
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
    } else if Self.awaitsDownload(url) {
      // Opening a file that is only in iCloud makes the read wait for the download on the main thread (G17).
      // No stamp, so returning to the window reads it again too.
      statuses[name] = (.unreadable, nil)
      startDownload(name, url)
      return .unreadable
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
        let keep = self.nearbyNames().union([fileName])
        self.thumbnails = self.thumbnails.filter { keep.contains($0.key) }
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
    downloading.removeAll()
    generation += 1
  }

  /// Number of decoded thumbnails held (for tests).
  var thumbnailCount: Int { thumbnails.count }

  /// Ask iCloud for the file and look again once it's here (checked every second for up to two minutes, off the main thread).
  private func startDownload(_ name: String, _ url: URL) {
    guard downloading.insert(name).inserted else { return }
    let generation = generation
    Task.detached(priority: .utility) {
      try? FileManager.default.startDownloadingUbiquitousItem(at: url)
      var waited = 0
      while waited < 120, Self.awaitsDownload(url) {
        try? await Task.sleep(for: .seconds(1))
        waited += 1
      }
      await MainActor.run { [weak self] in
        guard let self, self.generation == generation else { return }
        self.downloading.remove(name)
        self.statuses[name] = nil
        self.onStatusChanged(name)
      }
    }
  }

  /// An iCloud file whose contents aren't on this Mac yet. Reads only metadata, so it doesn't trigger the download itself.
  nonisolated private static func awaitsDownload(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
      values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus
    else { return false }
    return status == .notDownloaded
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
