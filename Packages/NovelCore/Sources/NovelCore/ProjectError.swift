import Foundation

/// 작품 파일을 다루다 생기는 오류. 화면에 보여줄 설명은 앱 쪽에서 붙인다.
public enum ProjectError: Error, Equatable, Sendable {
  /// 같은 이름의 작품 폴더가 이미 있다. 덮어쓰지 않는다.
  case alreadyExists(URL)
  /// `project.json`이 없다.
  case missingProjectFile(URL)
  /// `project.json`을 읽을 수 없다(형식이 깨짐). 복구는 3단계에서 붙인다.
  case corruptProjectFile(URL)
  /// 앱이 아는 것보다 새 형식이다. 고치지 않고 열기를 거부한다.
  case newerSchemaVersion(found: Int, supported: Int)
  /// 회차나 노트 본문 파일이 없다.
  case missingTextFile(URL)
  /// 본문이 UTF-8 텍스트가 아니다.
  case notUTF8(URL)
  case writeFailed(URL, reason: String)
}
