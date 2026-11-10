import Foundation

/// 회차의 고유 ID. 파일 이름(`episodes/<ID>.md`)으로 쓰이고, 순서나 제목을 바꿔도 변하지 않는다.
public struct EpisodeID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  /// 새 ID. UUID를 소문자로 쓴다(파일 시스템이 대소문자를 구분하든 안 하든 같은 이름이 되도록).
  public static func make() -> EpisodeID { EpisodeID(rawValue: UUID().uuidString.lowercased()) }
  public var description: String { rawValue }

  public init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
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
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
