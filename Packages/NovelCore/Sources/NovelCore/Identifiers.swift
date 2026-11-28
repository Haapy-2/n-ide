import Foundation

/// 회차의 고유 ID. 파일 이름(`episodes/<ID>.md`)으로 쓰이고, 순서나 제목을 바꿔도 변하지 않는다.
public struct EpisodeID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  /// 새 ID. UUID를 소문자로 쓴다(파일 시스템이 대소문자를 구분하든 안 하든 같은 이름이 되도록).
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

/// 설정 노트의 고유 ID. 파일 이름(`notes/<ID>.md`)으로 쓰인다.
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

/// 그림의 고유 ID. 파일 이름(`images/<ID>.<확장자>`)의 확장자 앞부분이다. 확장자는 원고 줄에 있다.
public struct ImageID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static func make() -> ImageID { ImageID(rawValue: UUID().uuidString.lowercased()) }
  public var description: String { rawValue }

  /// `images/` 안 파일 이름에서 ID(확장자 앞부분). 확장자가 없으면 이름 전체.
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

/// 회차 묶음의 고유 ID. 파일과는 상관없고 `project.json`에만 있다.
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

/// 파일 이름으로 쓰이는 ID를 읽는다. `project.json`은 앱 밖에서 고칠 수 있어서, 경로를 벗어나는 값(`/`, `.`, `..`, NUL)은
/// 받지 않는다. 받으면 `episodes/../../x.md`처럼 작품 폴더 밖에 쓰게 된다. 던지면 깨진 `project.json`으로 보고 복구한다.
private func decodeFileNameID(from decoder: Decoder) throws -> String {
  let container = try decoder.singleValueContainer()
  let raw = try container.decode(String.self)
  guard !raw.isEmpty, raw != ".", raw != "..", !raw.contains("/"), !raw.contains("\0") else {
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "파일 이름으로 쓸 수 없는 ID")
  }
  return raw
}
