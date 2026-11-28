import AppKit
import ImageIO
import NovelCore
import XCTest
@testable import NovelEditor

/// Putting pictures into the manuscript (PLAN ch.19 #1·#3, 14-1 ③b): file first, then the line (G10), after composition (G9),
/// one undo unit that leaves the file (G2), formats other than PNG/JPEG/HEIC stored as PNG (G16), broken-box menu (G1·G4).
@MainActor
final class ImageInsertionTests: XCTestCase {
  private var folder: URL!
  private var store: ProjectStore!
  private var added: [ImageMeta] = []

  override func setUp() async throws {
    folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/tmp/image-insertion-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    store = try ProjectStore.create(at: folder.appending(path: "작품.novel"), title: "작품")
    added = []
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func picture(_ type: NSBitmapImageRep.FileType, width: Int = 120, height: Int = 80) -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemOrange.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: type, properties: [:])!
  }

  private func writeFile(_ name: String, _ data: Data) throws -> URL {
    let url = folder.appending(path: name)
    try data.write(to: url)
    return url
  }

  private func typeIdentifier(of url: URL) -> String? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
  }

  private func makeEditor(_ text: String) -> (NSScrollView, ManuscriptTextView) {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.setFrameSize(NSSize(width: 1100, height: 700))
    textView.project = store.layout
    textView.onImagesAdded = { [unowned self] in added += $0 }
    textView.replaceAllText(with: text)
    textView.layoutManager!.ensureLayout(for: textView.textContainer!)
    textView.episodeUndoManager.groupsByEvent = false
    return (scrollView, textView)
  }

  private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async {
    let end = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
  }

  private func imageFiles() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: store.layout.imagesFolder.path(percentEncoded: false)))?.sorted() ?? []
  }

  // MARK: - Writing files

  func testPNGAndJPEGAreCopiedByteForByte() throws {
    for (type, ext) in [(NSBitmapImageRep.FileType.png, "png"), (.jpeg, "jpg")] {
      let data = picture(type)
      let imported = try ImageImporter.write(.file(writeFile("원본.\(ext)", data)), to: store)
      XCTAssertTrue(imported.fileName.hasSuffix(".\(ext)"))
      XCTAssertEqual(FileManager.default.contents(atPath: store.layout.imageFile(named: imported.fileName).path), data)
      XCTAssertEqual(imported.meta.name, "원본")
      XCTAssertEqual(imported.meta.id, ImageID(fileName: imported.fileName))
    }
  }

  func testGIFAndTIFFAreStoredAsPNG() throws {
    for (type, ext) in [(NSBitmapImageRep.FileType.gif, "gif"), (.tiff, "tiff")] {
      let imported = try ImageImporter.write(.file(writeFile("움짤.\(ext)", picture(type))), to: store)
      XCTAssertTrue(imported.fileName.hasSuffix(".png"), imported.fileName)
      XCTAssertEqual(typeIdentifier(of: store.layout.imageFile(named: imported.fileName)), "public.png")
    }
  }

  func testCopiedPictureDataIsNamedPlainly() throws {
    let imported = try ImageImporter.write(.data(picture(.tiff)), to: store)
    XCTAssertTrue(imported.fileName.hasSuffix(".png"))
    XCTAssertEqual(imported.meta.name, "그림")
  }

  func testNonImageIsRefusedAndWritesNothing() throws {
    let url = try writeFile("메모.png", Data("그림 아님".utf8))
    XCTAssertThrowsError(try ImageImporter.write(.file(url), to: store))
    XCTAssertEqual(imageFiles(), [])
  }

  // MARK: - Pasteboard

  func testPasteboardFilesWinAndTextBlocksPictureData() throws {
    let pasteboard = NSPasteboard(name: .init("NovelEditorTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let png = try writeFile("a.png", picture(.png))
    let text = try writeFile("a.txt", Data("글".utf8))

    pasteboard.clearContents()
    pasteboard.writeObjects([png as NSURL])
    pasteboard.setData(picture(.tiff), forType: .tiff)
    guard case .file(let url)? = ImageImporter.sources(on: pasteboard)?.first else { return XCTFail("file expected") }
    XCTAssertEqual(url.lastPathComponent, "a.png")

    pasteboard.clearContents()
    pasteboard.writeObjects([text as NSURL])
    XCTAssertNil(ImageImporter.sources(on: pasteboard), "a non-image file pastes as text")

    pasteboard.clearContents()
    pasteboard.setData(picture(.tiff), forType: .tiff)
    guard case .data? = ImageImporter.sources(on: pasteboard)?.first else { return XCTFail("picture data expected") }

    pasteboard.clearContents()
    pasteboard.setString("복사한 글", forType: .string)
    pasteboard.setData(picture(.tiff), forType: .tiff)
    XCTAssertNil(ImageImporter.sources(on: pasteboard), "text with a rendered picture pastes as text")
  }

  // MARK: - Inserting

  func testInsertWritesTheFileThenTheLineAndOneUndoRemovesOnlyTheLine() async throws {
    let (_, textView) = makeEditor("앞문장뒷문장")
    textView.setSelectedRange(NSRange(location: 3, length: 0))
    textView.insertImages([.data(picture(.png))])
    await waitUntil { textView.string.contains("![](") }

    let files = imageFiles()
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(textView.string, "앞문장\n![](../images/\(files[0]))\n뒷문장")
    XCTAssertEqual(textView.selectedRange().location, ("앞문장\n![](../images/\(files[0]))" as NSString).length)
    XCTAssertEqual(added.map(\.id), [ImageID(fileName: files[0])])
    XCTAssertEqual(textView.manuscriptLayout!.imageLines.entries.count, 1)

    XCTAssertEqual(textView.episodeUndoManager.undoActionName, "그림 넣기")
    textView.undo(nil)
    XCTAssertEqual(textView.string, "앞문장뒷문장")
    XCTAssertEqual(imageFiles(), files, "undo leaves the file (G2)")
    textView.redo(nil)
    XCTAssertEqual(textView.string, "앞문장\n![](../images/\(files[0]))\n뒷문장")
  }

  func testSeveralPicturesGoInAsOneUndoUnit() async throws {
    let (_, textView) = makeEditor("첫 줄\n")
    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.insertImages([.data(picture(.png)), .data(picture(.jpeg))])
    await waitUntil { textView.manuscriptLayout!.imageLines.entries.count == 2 }
    XCTAssertEqual(textView.manuscriptLayout!.imageLines.entries.count, 2)
    textView.undo(nil)
    XCTAssertEqual(textView.string, "첫 줄\n")
  }

  func testLineWaitsForCompositionToEnd() async throws {
    let (_, textView) = makeEditor("문장")
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.insertImages([.data(picture(.png))])
    // The test editor turns off per-event undo groups, and composition records undo; outside a group that throws.
    textView.episodeUndoManager.beginUndoGrouping()
    textView.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    await waitUntil { !self.imageFiles().isEmpty }
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(textView.hasMarkedText())
    XCTAssertEqual(textView.string, "문장ㅎ", "no edit while composing")
    textView.unmarkText()
    textView.episodeUndoManager.endUndoGrouping()
    await waitUntil { textView.string.contains("![](") }
    XCTAssertEqual(textView.string, "문장ㅎ\n![](../images/\(imageFiles()[0]))")
  }

  func testEpisodeSwitchMeanwhileKeepsTheFileButAddsNoLine() async throws {
    let (_, textView) = makeEditor("1화 본문")
    textView.insertImages([.data(picture(.png))])
    textView.replaceAllText(with: "2화 본문")
    await waitUntil { !self.added.isEmpty }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(textView.string, "2화 본문")
    XCTAssertEqual(imageFiles().count, 1)
    XCTAssertEqual(added.count, 1, "the name is kept so the file shows as an unused picture")
  }

  func testUnreadableFileShowsANoticeAndChangesNothing() async throws {
    let (_, textView) = makeEditor("문장")
    var notices: [String] = []
    textView.onNotice = { notices.append($0) }
    textView.insertImages([.file(try writeFile("깨짐.png", Data([1, 2, 3])))])
    await waitUntil { !notices.isEmpty }
    XCTAssertEqual(textView.string, "문장")
    XCTAssertTrue(notices.first?.contains("읽지 못해") == true, notices.description)
  }

  // MARK: - Broken box

  private func center(of entry: ImageLineIndex.Entry, in textView: ManuscriptTextView) -> NSPoint {
    let rect = textView.manuscriptLayout!.imageRect(for: entry)
    return NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
  }

  func testBrokenBoxOffersReplacementAndShownPictureDoesNot() throws {
    let name = try store.addImage(picture(.png), fileExtension: "png")
    let (_, textView) = makeEditor("![](../images/없음.png)\n문장\n![](../images/\(name))")
    let entries = textView.manuscriptLayout!.imageLines.entries
    XCTAssertEqual(textView.brokenImageMenuItems(at: center(of: entries[0], in: textView)).map(\.title), ["다른 그림으로 바꾸기…"])
    XCTAssertEqual(textView.brokenImageMenuItems(at: center(of: entries[1], in: textView)), [])
  }

  func testOutsidePictureCanBeCopiedIntoTheProjectAndUndone() async throws {
    let outside = try writeFile("바탕화면그림.png", picture(.png))
    let line = "![](\(outside.path))"
    let (_, textView) = makeEditor("앞\n\(line)\n뒤")
    let entry = textView.manuscriptLayout!.imageLines.entries[0]
    let items = textView.brokenImageMenuItems(at: center(of: entry, in: textView))
    XCTAssertEqual(items.map(\.title), ["다른 그림으로 바꾸기…", "작품에 넣기"])
    NSApp.sendAction(items[1].action!, to: items[1].target, from: items[1])
    await waitUntil { !textView.string.contains(outside.path) }

    let files = imageFiles()
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(textView.string, "앞\n![](../images/\(files[0]))\n뒤")
    XCTAssertEqual(added.first?.name, "바탕화면그림")
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "the outside file is copied, not moved")
    textView.undo(nil)
    XCTAssertEqual(textView.string, "앞\n\(line)\n뒤")
  }

  func testWebPictureIsNeverDownloaded() {
    let (_, textView) = makeEditor("![](https://example.com/a.png)")
    let entry = textView.manuscriptLayout!.imageLines.entries[0]
    XCTAssertEqual(textView.brokenImageMenuItems(at: center(of: entry, in: textView)).map(\.title), ["다른 그림으로 바꾸기…"])
  }
}
