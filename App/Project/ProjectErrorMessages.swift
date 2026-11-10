import Foundation
import NovelCore

extension ProjectError {
  /// 사용자에게 보여줄 한국어 설명.
  var userMessage: String {
    switch self {
    case .alreadyExists(let url):
      "‘\(url.lastPathComponent)’이(가) 이미 있어요. 덮어쓰지 않았어요. 다른 이름을 골라 주세요."
    case .missingProjectFile:
      "작품 폴더가 아니거나 작품 정보(project.json)와 회차 파일을 찾을 수 없어요. 아무것도 바꾸지 않았어요."
    case .corruptProjectFile:
      "작품 정보(project.json)를 읽을 수 없어요."
    case .newerSchemaVersion(let found, let supported):
      "더 새 버전의 앱으로 만든 작품이라 열 수 없어요(형식 \(found), 이 앱은 \(supported)까지). 파일은 그대로 두었어요."
    case .missingTextFile(let url):
      "본문 파일을 찾을 수 없어요: \(url.lastPathComponent)"
    case .notUTF8(let url):
      "본문 파일이 UTF-8 텍스트가 아니라 열 수 없어요: \(url.lastPathComponent)"
    case .writeFailed(let url, let reason):
      "\(url.lastPathComponent)을(를) 저장하지 못했어요. (\(reason))"
    }
  }
}
