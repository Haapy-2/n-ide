import Foundation

/// 작품 폴더에 저장하지 못한 원고를 작품 밖 다른 폴더에 따로 둔다. 앱이 죽어도 다음에 그 작품을 열 때 되살린다.
/// 작품 폴더를 못 쓰게 만든 원인(권한, 디스크 가득, 동기화 폴더 잠김)이 백업까지 막지 않도록 작품 밖에 둔다.
/// 폴더 안 모양: `<회차ID>.md`(본문 그대로, 사람이 열어 봐도 됨)와 `<회차ID>.json`(제목·시각).
/// 회차 ID로 찾으므로 Finder에서 작품 폴더를 옮겨도 이어진다.
public struct EmergencyBackup: Sendable {
  public struct Entry: Equatable, Sendable {
    public let episodeID: EpisodeID
    public let text: String
    public let episodeTitle: String
    public let projectTitle: String
    /// 정보 파일을 읽지 못했으면 nil.
    public let savedAt: Date?
  }

  private struct Info: Codable {
    var episodeTitle: String
    var projectTitle: String
    var savedAt: Date
  }

  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  /// 본문을 먼저 쓰고 정보를 쓴다. 정보 쓰기가 실패해도 본문은 남는다.
  public func write(
    _ text: String, episode id: EpisodeID, episodeTitle: String, projectTitle: String, at date: Date = Date()
  ) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try AtomicFile.write(Data(text.utf8), to: textURL(id))
    let info = Info(episodeTitle: episodeTitle, projectTitle: projectTitle, savedAt: date)
    try AtomicFile.write(try Self.encoder.encode(info), to: infoURL(id))
  }

  /// 이 회차들의 백업. 폴더 목록을 한 번만 읽는다(보통 비어 있다). 본문을 읽지 못한 백업은 건너뛴다.
  public func entries(for ids: Set<EpisodeID>) -> [Entry] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
      return []
    }
    return names.compactMap { name -> Entry? in
      guard name.hasSuffix(".md") else { return nil }
      let id = EpisodeID(rawValue: String(name.dropLast(3)))
      guard ids.contains(id),
        let data = try? Data(contentsOf: textURL(id)),
        let text = String(data: data, encoding: .utf8)
      else { return nil }
      let info = (try? Data(contentsOf: infoURL(id))).flatMap { try? Self.decoder.decode(Info.self, from: $0) }
      return Entry(
        episodeID: id, text: text, episodeTitle: info?.episodeTitle ?? "", projectTitle: info?.projectTitle ?? "",
        savedAt: info?.savedAt)
    }
    .sorted { $0.episodeID.rawValue < $1.episodeID.rawValue }
  }

  /// 백업을 지운다. 없으면 아무것도 안 한다. 원고가 작품 폴더에 안전하게 쓰인 뒤에만 부른다.
  public func remove(_ id: EpisodeID) throws {
    for url in [textURL(id), infoURL(id)] where FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// 백업 두 파일의 위치(휴지통으로 옮길 때).
  public func files(of id: EpisodeID) -> [URL] {
    [textURL(id), infoURL(id)].filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
  }

  /// 백업 본문을 작품의 회차 파일로 되살린다. 지금 파일 본문이 다르면 먼저 `복원 전` 스냅샷으로 남겨,
  /// 되살린 뒤에도 스냅샷 판에서 비교하거나 되돌릴 수 있다. 다 쓴 뒤에만 백업을 지운다.
  /// 파일과 같으면(이미 저장됐던 것) 쓰지 않고 백업만 지운다. 되살려 썼으면 true.
  @discardableResult
  /// 파일이 있는데 읽지 못하면(UTF-8이 아님 등) 던진다. 스냅샷 없이 덮으면 그 내용이 어디에도 남지 않는다.
  public func restore(_ entry: Entry, into store: ProjectStore, memo: String) throws -> Bool {
    let file = store.layout.episodeFile(entry.episodeID).path(percentEncoded: false)
    let current = FileManager.default.fileExists(atPath: file) ? try store.readEpisode(entry.episodeID) : nil
    guard current != entry.text else {
      try remove(entry.episodeID)
      return false
    }
    if let current {
      try store.writeSnapshot(current, episode: entry.episodeID, kind: .restore, memo: memo)
    }
    try store.writeEpisode(entry.text, id: entry.episodeID)
    try remove(entry.episodeID)
    return true
  }

  private func textURL(_ id: EpisodeID) -> URL {
    folder.appending(path: "\(id.rawValue).md", directoryHint: .notDirectory)
  }

  private func infoURL(_ id: EpisodeID) -> URL {
    folder.appending(path: "\(id.rawValue).json", directoryHint: .notDirectory)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
