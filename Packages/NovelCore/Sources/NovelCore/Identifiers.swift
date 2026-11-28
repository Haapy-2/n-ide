import Foundation

/// Unique episode ID. Used as the file name (`episodes/<ID>.md`) and never changes with order or title.
public struct EpisodeID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  /// New ID. Lowercase UUID (same name whether or not the file system is case-sensitive).
  public static func make() -> EpisodeID { EpisodeID(rawValue: UUID().uuidString.lowercased()) }
  public var description: String { rawValue }

  public init(from decoder: Decoder) throws {
    rawValue = try decodeFileNameID(from: decoder)
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Unique ID of a setting note. Used as the file name (`notes/<ID>.md`).
public struct NoteID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static func make() -> NoteID { NoteID(rawValue: UUID().uuidString.lowercased()) }
  public var description: String { rawValue }

  public init(from decoder: Decoder) throws {
    rawValue = try decodeFileNameID(from: decoder)
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Unique image ID. The part of the file name (`images/<ID>.<ext>`) before the extension. The extension lives in the manuscript line.
public struct ImageID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static func make() -> ImageID { ImageID(rawValue: UUID().uuidString.lowercased()) }
  public var description: String { rawValue }

  /// ID from a file name inside `images/` (the part before the extension). The whole name if there's no extension.
  public init(fileName: String) {
    rawValue = (fileName as NSString).deletingPathExtension
  }

  public init(from decoder: Decoder) throws {
    rawValue = try decodeFileNameID(from: decoder)
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Unique episode group ID. Unrelated to files; exists only in `project.json`.
public struct GroupID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static func make() -> GroupID { GroupID(rawValue: UUID().uuidString.lowercased()) }
  public var description: String { rawValue }

  public init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Read an ID used as a file name. `project.json` can be edited outside the app, so values escaping the path (`/`, `.`, `..`, NUL)
/// are rejected. Accepting them would write outside the project folder like `episodes/../../x.md`. Throwing treats `project.json` as broken and recovers.
private func decodeFileNameID(from decoder: Decoder) throws -> String {
  let container = try decoder.singleValueContainer()
  let raw = try container.decode(String.self)
  guard !raw.isEmpty, raw != ".", raw != "..", !raw.contains("/"), !raw.contains("\0") else {
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "파일 이름으로 쓸 수 없는 ID")
  }
  return raw
}
