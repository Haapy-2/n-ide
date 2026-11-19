import Foundation

/// 작품 폴더(`.novel` 패키지)의 형식 정보. 앱과 NovelCore가 같은 값을 쓰도록 여기 한 곳에 둔다.
public enum ProjectFormat {
  /// 작품 폴더 확장자. Finder에서 문서 패키지로 등록된다.
  public static let packageExtension = "novel"
  /// `project.json`의 현재 형식 버전. 형식을 바꾸면 올리고, 옛 버전을 옮기는 코드를 함께 넣는다.
  /// 2(2026-11-20): 회차 묶음(`groups`, 회차의 `group`)을 더함. 1은 묶음이 없는 것으로 그대로 읽힌다.
  /// 옛 앱이 2를 열면 묶음을 모른 채 저장해 묶음이 사라지므로, 옛 앱은 2를 거부하게 버전을 올렸다.
  public static let currentSchemaVersion = 2
}
