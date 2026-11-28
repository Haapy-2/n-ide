import Foundation
import Testing
@testable import NovelCore

struct ImageLineTests {
  private let id = "3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f"

  // MARK: - Treated as image lines

  @Test func appInsertedLineIsAnImage() {
    let line = ImageLine.markdown(fileName: "\(id).png")
    #expect(line == "![](../images/\(id).png)")
    #expect(ImageLine.parse(line)?.source == .project(fileName: "\(id).png"))
  }

  @Test func imagesFolderWithoutDotsIsInProject() {
    #expect(ImageLine.parse("![](images/a.jpg)")?.source == .project(fileName: "a.jpg"))
  }

  @Test func leadingAndTrailingSpacesAndTabsAreAllowed() {
    #expect(ImageLine.parse("  \t![](../images/a.png) \t")?.source == .project(fileName: "a.png"))
  }

  @Test func percentEncodingIsDecoded() {
    #expect(ImageLine.parse("![](../images/%EC%82%BD%ED%99%94%201.png)")?.source == .project(fileName: "삽화 1.png"))
  }

  @Test func pathsOutsideTheProjectAreImagesButOutside() {
    #expect(ImageLine.parse("![](/Users/me/a.png)")?.source == .outside(path: "/Users/me/a.png"))
    #expect(ImageLine.parse("![](../../a.png)")?.source == .outside(path: "../../a.png"))
    #expect(ImageLine.parse("![](https://example.com/a.png)")?.source == .outside(path: "https://example.com/a.png"))
    #expect(ImageLine.parse("![](../images/sub/a.png)")?.source == .outside(path: "../images/sub/a.png"))
    #expect(ImageLine.parse("![](../images/..)")?.source == .outside(path: "../images/.."))
  }

  // MARK: - Left as text

  @Test func linesThatStayText() {
    let texts = [
      "",
      "그는 문을 열었다.",
      "![사진](../images/a.png)",
      "![](../images/a.png \"제목\")",
      "![](../images/a b.png)",
      "![]()",
      "<img src=\"../images/a.png\">",
      "그림: ![](../images/a.png)",
      "![](../images/a.png) 아래에 쓴 글",
      "![](../images/a.png)![](../images/b.png)",
      "[](../images/a.png)",
      "\u{3000}![](../images/a.png)",
      "![](../images/%ZZ.png)",
    ]
    for text in texts {
      #expect(ImageLine.parse(text) == nil, "\(text)")
    }
  }

  // MARK: - Paragraphs and order

  @Test func isImageLineLooksAtOneParagraph() {
    let text = "앞 글\n![](../images/a.png)\n뒤 글" as NSString
    #expect(ImageLine.isImageLine(text, paragraph: NSRange(location: 0, length: 3)) == false)
    #expect(ImageLine.isImageLine(text, paragraph: NSRange(location: 4, length: 20)) == true)
    #expect(ImageLine.isImageLine(text, paragraph: NSRange(location: 4, length: 0)) == false)
  }

  @Test func occurrencesAreInTextOrder() {
    let text = "첫 문단\n\n![](../images/b.png)\n\n가운데\r\n![](images/a.jpg)\n![사진](../images/c.png)\n![](/x.png)"
    let found = ImageLine.occurrences(in: text)
    #expect(found.map(\.line.source) == [
      .project(fileName: "b.png"), .project(fileName: "a.jpg"), .outside(path: "/x.png"),
    ])
    let source = text as NSString
    #expect(found.map { source.substring(with: $0.range) } == [
      "![](../images/b.png)", "![](images/a.jpg)", "![](/x.png)",
    ])
  }

  @Test func sameImageTwiceIsCountedTwice() {
    let line = ImageLine.markdown(fileName: "a.png")
    #expect(ImageLine.occurrences(in: "\(line)\n글\n\(line)").count == 2)
  }

  @Test func mayContainImageLine() {
    #expect(ImageLine.mayContainImageLine("글\n![](x)") == true)
    #expect(ImageLine.mayContainImageLine("![사진](x) 글") == false)
    #expect(ImageLine.mayContainImageLine("") == false)
  }

  // MARK: - Other features skip image lines

  @Test func characterCountSkipsImageLines() {
    let line = ImageLine.markdown(fileName: "\(id).png")
    let text = "그는 문을 열었다.\n\n\(line)\n\n  \(line)  \r\n카페 안 (그림 설명)"
    #expect(CharacterCount(counting: text) == CharacterCount(counting: "그는 문을 열었다.\n\n\n\n\r\n카페 안 (그림 설명)"))
    #expect(CharacterCount(counting: line) == .zero)
  }

  @Test func characterCountStillCountsLinesThatStayText() {
    let text = "![사진](../images/a.png)"
    #expect(CharacterCount(counting: text).withSpaces == text.count)
  }

  @Test func searchAndReplaceSkipImageLines() {
    let text = "png 파일\n![](../images/a.png)\n끝 png"
    #expect(TextSearch.matches(of: "png", in: text, caseSensitive: false).map(\.line) == [1, 3])
    #expect(TextReplace.count(of: "images", in: text, caseSensitive: false) == 0)
    let replaced = TextReplace.replacing("png", with: "jpg", in: text, caseSensitive: false)
    #expect(replaced?.text == "jpg 파일\n![](../images/a.png)\n끝 jpg")
    #expect(replaced?.count == 2)
  }

  @Test func multiCursorSkipsImageLines() {
    let text = "png 하나\n![](../images/a.png)\npng 둘"
    var cursor = MultiCursor(selection: NSRange(location: 0, length: 3), wholeWord: false)!
    #expect(cursor.addNext(in: text) == .added(NSRange(location: 28, length: 3)))
    #expect(cursor.addNext(in: text) == .noMore)
  }

  // MARK: - Image names in project.json

  @Test func imageNamesRoundTripAndEmptyIsNotWritten() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let plain = try encoder.encode(ProjectFile(title: "작품"))
    #expect(String(decoding: plain, as: UTF8.self).contains("images") == false)
    #expect(try JSONDecoder().decode(ProjectFile.self, from: plain).images == [])

    let named = ProjectFile(title: "작품", images: [ImageMeta(id: ImageID(rawValue: id), name: "카페 삽화 최종")])
    let decoded = try JSONDecoder().decode(ProjectFile.self, from: try encoder.encode(named))
    #expect(decoded.images == named.images)
  }

  @Test func duplicateImageIDsKeepTheFirst() throws {
    let json = """
    {"schemaVersion":2,"title":"t","episodes":[],"notes":[],"settings":{"defaultEpisodeGoal":5000},
     "images":[{"id":"a","name":"첫째"},{"id":"a","name":"둘째"}]}
    """
    let project = try JSONDecoder().decode(ProjectFile.self, from: Data(json.utf8))
    #expect(project.images == [ImageMeta(id: ImageID(rawValue: "a"), name: "첫째")])
  }

  @Test func imageIDThatEscapesTheFolderIsRejected() {
    let json = """
    {"schemaVersion":2,"title":"t","episodes":[],"notes":[],"settings":{"defaultEpisodeGoal":5000},
     "images":[{"id":"../x","name":"n"}]}
    """
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ProjectFile.self, from: Data(json.utf8)) }
  }

  @Test func nameAndIDFromFileNames() {
    #expect(ImageMeta.name(fromOriginalFileName: "카페 삽화 최종.png") == "카페 삽화 최종")
    #expect(ImageMeta.name(fromOriginalFileName: "DALL·E 2026-11-28 10.21.33.webp") == "DALL·E 2026-11-28 10.21.33")
    #expect(ImageMeta.name(fromOriginalFileName: ".png") == ".png")
    #expect(ImageMeta.name(fromOriginalFileName: "  ") == "그림")
    #expect(ImageID(fileName: "\(id).heic").rawValue == id)
  }
}
