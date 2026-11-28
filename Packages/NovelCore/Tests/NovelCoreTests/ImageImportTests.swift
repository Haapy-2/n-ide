import Foundation
import Testing
@testable import NovelCore

struct ImageImportTests {
  // MARK: - Stored formats

  @Test func pngJpegHeicAreStoredAsIsAndOthersBecomePNG() {
    #expect(ImageImport.storedExtension(forTypeIdentifier: "public.png") == "png")
    #expect(ImageImport.storedExtension(forTypeIdentifier: "public.jpeg") == "jpg")
    #expect(ImageImport.storedExtension(forTypeIdentifier: "public.heic") == "heic")
    #expect(ImageImport.storedExtension(forTypeIdentifier: "com.compuserve.gif") == nil)
    #expect(ImageImport.storedExtension(forTypeIdentifier: "org.webmproject.webp") == nil)
    #expect(ImageImport.storedExtension(forTypeIdentifier: "com.adobe.photoshop-image") == nil)
    #expect(ImageImport.storedExtension(forTypeIdentifier: "public.tiff") == nil)
  }

  // MARK: - Writing the file

  @Test func addImageWritesANewUUIDFileInsideImages() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    let data = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    let name = try store.addImage(data, fileExtension: "png")
    #expect(name.hasSuffix(".png"))
    #expect(name == name.lowercased())
    #expect(UUID(uuidString: ImageID(fileName: name).rawValue) != nil)
    #expect(FileManager.default.contents(atPath: store.layout.imageFile(named: name).path(percentEncoded: false)) == data)
    // No temp file is left behind.
    #expect(try folder.fileNames(in: store.layout.imagesFolder) == [name])
    // The line the app inserts points at that file.
    #expect(ImageLine.parse(ImageLine.markdown(fileName: name))?.source == .project(fileName: name))
  }

  @Test func addImageRecreatesADeletedImagesFolder() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    try? FileManager.default.removeItem(at: store.layout.imagesFolder)
    let name = try store.addImage(Data([1]), fileExtension: "jpg")
    #expect(FileManager.default.fileExists(atPath: store.layout.imageFile(named: name).path(percentEncoded: false)))
  }

  @Test func eachAddImageGetsItsOwnFile() throws {
    let folder = try TestFolder()
    defer { folder.remove() }
    let store = try ProjectStore.create(at: folder.url.appending(path: "작품.novel"), title: "작품")
    let first = try store.addImage(Data([1]), fileExtension: "png")
    let second = try store.addImage(Data([1]), fileExtension: "png")
    #expect(first != second)
    #expect(try folder.fileNames(in: store.layout.imagesFolder).count == 2)
  }

  // MARK: - Placing lines

  private func apply(_ text: String, _ range: NSRange, _ names: [String]) -> (String, Int) {
    let plan = ImageImport.insertion(fileNames: names, in: text as NSString, replacing: range)
    return ((text as NSString).replacingCharacters(in: range, with: plan.text), plan.caret)
  }

  @Test func midLineInsertionSplitsTheLine() {
    let (text, caret) = apply("앞문장뒷문장", NSRange(location: 3, length: 0), ["a.png"])
    #expect(text == "앞문장\n![](../images/a.png)\n뒷문장")
    #expect(caret == ("앞문장\n![](../images/a.png)" as NSString).length)
  }

  @Test func onAnEmptyLineNothingIsAdded() {
    let (text, _) = apply("첫 줄\n\n끝 줄", NSRange(location: 4, length: 0), ["a.png"])
    #expect(text == "첫 줄\n![](../images/a.png)\n끝 줄")
  }

  @Test func atLineStartOnlyANewlineAfter() {
    let (text, caret) = apply("첫 줄\n둘째 줄", NSRange(location: 4, length: 0), ["a.png"])
    #expect(text == "첫 줄\n![](../images/a.png)\n둘째 줄")
    #expect(caret == ("첫 줄\n![](../images/a.png)" as NSString).length)
  }

  @Test func atLineEndOnlyANewlineBefore() {
    let (text, _) = apply("첫 줄\n둘째 줄", NSRange(location: 3, length: 0), ["a.png"])
    #expect(text == "첫 줄\n![](../images/a.png)\n둘째 줄")
  }

  @Test func emptyBodyGetsJustTheLine() {
    let (text, caret) = apply("", NSRange(location: 0, length: 0), ["a.png"])
    #expect(text == "![](../images/a.png)")
    #expect(caret == (text as NSString).length)
  }

  @Test func severalImagesGetALineEachAndASelectionIsReplaced() {
    let (text, _) = apply("앞 지울말 뒤", NSRange(location: 2, length: 3), ["a.png", "b.jpg"])
    #expect(text == "앞 \n![](../images/a.png)\n![](../images/b.jpg)\n 뒤")
    #expect(ImageLine.occurrences(in: text).count == 2)
  }

  @Test func rightAfterAnImageLineStartsANewLine() {
    let body = "![](../images/a.png)"
    let (text, _) = apply(body, NSRange(location: (body as NSString).length, length: 0), ["b.png"])
    #expect(text == "![](../images/a.png)\n![](../images/b.png)")
    #expect(ImageLine.occurrences(in: text).count == 2)
  }

  // MARK: - Outside files (G4)

  @Test func outsidePathsResolveToLocalFilesButNeverTheWeb() {
    let episodes = URL(filePath: "/p/작품.novel/episodes", directoryHint: .isDirectory)
    #expect(ImageImport.outsideFile("https://example.com/a.png", episodesFolder: episodes) == nil)
    #expect(ImageImport.outsideFile("http://example.com/a.png", episodesFolder: episodes) == nil)
    #expect(ImageImport.outsideFile("/Users/me/a.png", episodesFolder: episodes)?.path == "/Users/me/a.png")
    #expect(ImageImport.outsideFile("file:///Users/me/a.png", episodesFolder: episodes)?.path == "/Users/me/a.png")
    #expect(ImageImport.outsideFile("../../그림/a.png", episodesFolder: episodes)?.path == "/p/그림/a.png")
  }
}
