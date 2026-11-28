import Foundation

/// Atomic write: write fully to a temp file in the same folder, flush to disk, then replace with a single rename.
/// The OS performs a rename in one step, so even if the app dies midway only the old or the new file remains,
/// never a half-written one.
enum AtomicFile {
  /// A file with the same name already existed when writing with `replacing: false`. Nothing changed.
  struct AlreadyExists: Error {}

  /// - Parameter replacing: false never overwrites an existing file (snapshots). Throws `AlreadyExists` if present.
  ///   "Check then write" lets another write slip in between check and write, so the OS does both in one step.
  /// - Parameter fullSync: false sends only to the storage device (fsync) without flushing the device cache (3.2 → 0.16 ms).
  ///   F_FULLFSYNC flushes the whole device cache, so a file written right after with F_FULLFSYNC flushes this one too.
  ///   Disabled only where that ordering is guaranteed (replace all's snapshot → body).
  static func write(_ data: Data, to destination: URL, replacing: Bool = true, fullSync: Bool = true) throws {
    let folder = destination.deletingLastPathComponent()
    // The name starts with a dot to hide it in Finder. Must be the same folder for the rename to be atomic.
    let temp = folder.appending(
      path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)

    // FileManager.createFile doesn't report why it failed, so open is used (errno distinguishes permission vs. space).
    let descriptor = open(temp.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard descriptor >= 0 else {
      let code = errno
      throw ProjectError.writeFailed(
        destination, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
    }
    do {
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? handle.close() }
      try handle.write(contentsOf: data)
      // Flushed before renaming so the content survives a sudden power loss.
      // On Apple devices fsync doesn't flush the storage device's cache, so F_FULLFSYNC is used (measured 0.2 → 2.9 ms, off the main thread).
      // File systems that don't support it (some network drives) fall back to fsync.
      if !fullSync || fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 {
        try handle.synchronize()
      }
    } catch {
      try? FileManager.default.removeItem(at: temp)
      throw ProjectError.writeFailed(destination, reason: error.localizedDescription, problem: WriteProblem(error: error))
    }

    let tempPath = temp.path(percentEncoded: false)
    let destinationPath = destination.path(percentEncoded: false)
    if replacing {
      if rename(tempPath, destinationPath) != 0 {
        let code = errno
        try? FileManager.default.removeItem(at: temp)
        throw ProjectError.writeFailed(destination, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
      }
    } else {
      // link fails if the new name exists; on success the finished file appears under that name in one step. Then only the temp name is removed.
      if link(tempPath, destinationPath) != 0 {
        let code = errno
        if code == EEXIST {
          try? FileManager.default.removeItem(at: temp)
          throw AlreadyExists()
        }
        // File systems that can't make hard links (exFAT/FAT external disks, some network drives) use another method.
        try placeWithoutLink(temp: tempPath, destination: destinationPath, url: destination)
        return
      }
      unlink(tempPath)
    }
  }

  /// Instead of `link`: claim the name with an empty file first (O_EXCL, the OS refuses if it exists), then swap the finished temp file over it.
  /// The claimed name belongs to this write only, so overwriting it never clobbers someone else's file. A crash before the swap could leave an empty file, so it's not used when `link` works.
  static func placeWithoutLink(temp: String, destination: String, url: URL) throws {
    let placeholder = open(destination, O_CREAT | O_EXCL | O_WRONLY, 0o644)
    guard placeholder != -1 else {
      let code = errno
      unlink(temp)
      if code == EEXIST { throw AlreadyExists() }
      throw ProjectError.writeFailed(url, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
    }
    close(placeholder)
    if rename(temp, destination) != 0 {
      let code = errno
      unlink(temp)
      unlink(destination)
      throw ProjectError.writeFailed(url, reason: String(cString: strerror(code)), problem: WriteProblem(errno: code))
    }
  }
}
