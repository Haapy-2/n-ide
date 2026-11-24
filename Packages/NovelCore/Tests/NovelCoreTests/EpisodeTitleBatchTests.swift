import Testing
@testable import NovelCore

/// 여러 회차 이름 바꾸기 규칙. 창의 미리 보기와 적용이 같은 결과를 쓰므로 여기 결과가 곧 바뀌는 이름이다.
struct EpisodeTitleBatchTests {
  @Test func replaceFindsLikeSearch() {
    let titles = ["민준의 귀환", "MINJUN", "민준과 민준", "도윤"]
    let result = EpisodeTitleBatch.titles(titles, by: .replace(find: "민준", with: "도윤"))
    #expect(result == ["도윤의 귀환", "MINJUN", "도윤과 도윤", "도윤"])
    #expect(EpisodeTitleBatch.titles(["Minjun"], by: .replace(find: "minjun", with: "Doyun")) == ["Doyun"],
      "영문 대소문자는 무시")
    // 자모를 따로 적은 한글(NFD)도 찾는다.
    let decomposed = "민준".decomposedStringWithCanonicalMapping + " 1화"
    #expect(EpisodeTitleBatch.titles([decomposed], by: .replace(find: "민준", with: "도윤")) == ["도윤 1화"])
  }

  @Test func emptyFindChangesNothing() {
    #expect(EpisodeTitleBatch.titles(["1화", ""], by: .replace(find: "", with: "x")) == ["1화", ""])
  }

  @Test func replaceCanEmptyTheTitle() {
    #expect(EpisodeTitleBatch.titles(["  임시  "], by: .replace(find: "임시", with: "")) == [""], "남은 공백도 자른다")
  }

  @Test func affixAddsBothSides() {
    let result = EpisodeTitleBatch.titles(["귀환", ""], by: .affix(prefix: "1부 ", suffix: " (수정)"))
    #expect(result == ["1부 귀환 (수정)", "1부  (수정)"])
  }

  @Test func numberedFollowsGivenOrder() {
    let titles = ["가", "나", "다"]
    #expect(EpisodeTitleBatch.titles(titles, by: .numbered(name: "프롤로그", start: 1, numberFirst: false))
      == ["프롤로그 1", "프롤로그 2", "프롤로그 3"])
    #expect(EpisodeTitleBatch.titles(titles, by: .numbered(name: " 화 ", start: 9, numberFirst: true))
      == ["9 화", "10 화", "11 화"])
    #expect(EpisodeTitleBatch.titles(titles, by: .numbered(name: "", start: 0, numberFirst: false)) == ["0", "1", "2"])
  }
}
