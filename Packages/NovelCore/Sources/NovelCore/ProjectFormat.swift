import Foundation

/// 작품 폴더(`.novel` 패키지)의 형식 정보. 앱과 NovelCore가 같은 값을 쓰도록 여기 한 곳에 둔다.
public enum ProjectFormat {
  /// 작품 폴더 확장자. Finder에서 문서 패키지로 등록된다.
  public static let packageExtension = "novel"
  /// `project.json`의 현재 형식 버전. 형식을 바꾸면 올리고, 옛 버전을 옮기는 코드를 함께 넣는다.
  public static let currentSchemaVersion = 1
}
