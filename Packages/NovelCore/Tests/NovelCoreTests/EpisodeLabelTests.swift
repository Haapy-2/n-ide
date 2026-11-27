import Testing
@testable import NovelCore

/// 확인 창·판 제목에 들어가는 회차 이름과 조사. 사용자에게 그대로 보이는 문구다.
struct EpisodeLabelTests {
  @Test func numberOnlyWhenTitleIsEmptyOrSameNumber() {
    #expect(EpisodeLabel.text(number: 3, title: "") == "3화")
    #expect(EpisodeLabel.text(number: 3, title: "  ") == "3화")
    #expect(EpisodeLabel.text(number: 1, title: "1화") == "1화", "‘1화 1화’처럼 겹치지 않는다")
    #expect(EpisodeLabel.text(number: 1, title: "1화", quoted: true) == "1화")
  }

  @Test func titleThatAlreadyHasTheNumberIsNotRepeated() {
    #expect(EpisodeLabel.text(number: 3, title: "3화 첫 만남") == "3화 첫 만남")
    #expect(EpisodeLabel.text(number: 3, title: "제3화 첫 만남", quoted: true) == "‘제3화 첫 만남’")
  }

  @Test func otherTitlesGetTheNumberInFront() {
    #expect(EpisodeLabel.text(number: 3, title: "첫 만남") == "3화 첫 만남")
    #expect(EpisodeLabel.text(number: 3, title: "첫 만남", quoted: true) == "3화 ‘첫 만남’")
    #expect(EpisodeLabel.text(number: 3, title: "1화") == "3화 1화", "순서가 바뀌어 번호가 다르면 둘 다 보여야 알 수 있다")
    #expect(EpisodeLabel.text(number: 1, title: "13화") == "1화 13화")
  }

  @Test func particleFollowsFinalConsonant() {
    #expect(KoreanParticle.attach(.objectMarker, to: "검") == "검을")
    #expect(KoreanParticle.attach(.objectMarker, to: "1화") == "1화를")
    #expect(KoreanParticle.attach(.objectMarker, to: "3화 ‘첫 만남’") == "3화 ‘첫 만남’을", "닫는 따옴표는 건너뛴다")
    #expect(KoreanParticle.attach(.subjectMarker, to: "지금 저장") == "지금 저장이")
    #expect(KoreanParticle.attach(.subjectMarker, to: "스냅샷 보기…") == "스냅샷 보기…가", "말줄임표는 건너뛴다")
  }

  @Test func directionUsesRoAfterRieulAndVowel() {
    #expect(KoreanParticle.attach(.direction, to: "도윤") == "도윤으로")
    #expect(KoreanParticle.attach(.direction, to: "서울") == "서울로", "ㄹ 받침 뒤는 ‘로’")
    #expect(KoreanParticle.attach(.direction, to: "하나") == "하나로")
    #expect(KoreanParticle.attach(.direction, to: "'민준'") == "'민준'으로")
  }

  @Test func digitsAreReadAloud() {
    #expect(KoreanParticle.attach(.objectMarker, to: "10") == "10을")
    #expect(KoreanParticle.attach(.objectMarker, to: "2") == "2를")
    #expect(KoreanParticle.attach(.direction, to: "7") == "7로")
  }

  @Test func unknownEndingKeepsBothForms() {
    #expect(KoreanParticle.attach(.objectMarker, to: "Minjun") == "Minjun을(를)")
    #expect(KoreanParticle.attach(.direction, to: "Minjun") == "Minjun(으)로")
    #expect(KoreanParticle.attach(.subjectMarker, to: "⌘S") == "⌘S이(가)")
  }

  @Test func decomposedHangulIsRead() {
    let word = "검".decomposedStringWithCanonicalMapping
    #expect(KoreanParticle.attach(.objectMarker, to: word) == word + "을")
  }
}
