import AppKit
import NovelCore
import XCTest
@testable import NovelEditor

/// Image lines show as pictures but stay markdown in the text storage, and edit as one block (PLAN ch.19 #2·#3, 14-1 ③a).
@MainActor
final class ImageLineEditingTests: XCTestCase {
  private var folder: URL!
  private var project: ProjectLayout!
  private let none = NSRange(location: NSNotFound, length: 0)
  private let body = "첫 문장이다.\n![](../images/wide.png)\n그림 뒤 줄이다.\n\n![](../images/tall.png)\n마지막 줄."

  override func setUp() async throws {
    folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "build/tmp/image-lines-\(UUID().uuidString)")
    project = ProjectLayout(root: folder.appending(path: "작품.novel"))
    try FileManager.default.createDirectory(at: project.imagesFolder, withIntermediateDirectories: true)
    try writePNG("wide.png", width: 1600, height: 900)
    try writePNG("tall.png", width: 400, height: 700)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func writePNG(_ name: String, width: Int, height: Int) throws {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: project.imageFile(named: name), options: .atomic)
  }

  private func makeEditor(_ text: String? = nil) -> (NSScrollView, ManuscriptTextView) {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
    let textView = ManuscriptTextView.make()
    scrollView.documentView = textView
    textView.setFrameSize(NSSize(width: 1100, height: 700))
    textView.project = project
    textView.replaceAllText(with: text ?? body)
    textView.layoutManager!.ensureLayout(for: textView.textContainer!)
    textView.episodeUndoManager.groupsByEvent = false
    return (scrollView, textView)
  }

  private func entries(_ textView: ManuscriptTextView) -> [ImageLineIndex.Entry] {
    textView.manuscriptLayout!.imageLines.entries
  }

  private func lineRect(_ textView: ManuscriptTextView, at character: Int) -> NSRect {
    let layoutManager = textView.layoutManager!
    layoutManager.ensureLayout(for: textView.textContainer!)
    return layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: character), effectiveRange: nil)
  }

  private func undoably(_ textView: ManuscriptTextView, _ change: () -> Void) {
    textView.episodeUndoManager.beginUndoGrouping()
    change()
    textView.episodeUndoManager.endUndoGrouping()
  }

  // MARK: - Display

  func testImageLineIsAsTallAsThePictureFittedToTheBodyWidth() {
    let (_, textView) = makeEditor()
    let layout = textView.manuscriptLayout!
    let wide = entries(textView)[0]
    let size = layout.displaySize(of: wide.line)
    XCTAssertEqual(size.width, layout.maxImageWidth)
    XCTAssertEqual(size.height, (900 * layout.maxImageWidth / 1600).rounded())
    let line = lineRect(textView, at: wide.range.location)
    XCTAssertEqual(line.height, size.height + layout.imagePadding * 2)
    // The next line keeps the body line height and starts right below.
    let next = lineRect(textView, at: NSMaxRange(wide.range) + 1)
    XCTAssertEqual(next.minY, line.maxY)
    XCTAssertLessThan(next.height, 60)
  }

  func testSmallPictureIsNotEnlarged() {
    let (_, textView) = makeEditor()
    XCTAssertEqual(textView.manuscriptLayout!.displaySize(of: entries(textView)[1].line), NSSize(width: 400, height: 700))
  }

  func testStorageKeepsTheMarkdownAndHidesTheRest() {
    let (_, textView) = makeEditor()
    XCTAssertEqual(textView.string, body)
    let layoutManager = textView.layoutManager!
    let wide = entries(textView)[0].range
    XCTAssertEqual(layoutManager.propertyForGlyph(at: layoutManager.glyphIndexForCharacter(at: wide.location)), .controlCharacter)
    for index in (wide.location + 1)..<NSMaxRange(wide) {
      XCTAssertEqual(layoutManager.propertyForGlyph(at: layoutManager.glyphIndexForCharacter(at: index)), .null)
    }
  }

  func testImageLineIsOneLineFragment() {
    let (_, textView) = makeEditor()
    let layoutManager = textView.layoutManager!
    var fragments = 0
    layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { _, _, _, _, _ in
      fragments += 1
    }
    XCTAssertEqual(fragments, body.components(separatedBy: "\n").count)
  }

  func testMissingAndOutsidePicturesShowABox() {
    let (_, textView) = makeEditor("앞\n![](../images/gone.png)\n![](/Users/someone/a.png)\n뒤")
    let layout = textView.manuscriptLayout!
    let found = entries(textView)
    XCTAssertEqual(layout.images.status(of: found[0].line), .missing)
    XCTAssertEqual(layout.images.status(of: found[1].line), .outside)
    XCTAssertEqual(lineRect(textView, at: found[0].range.location).height, ManuscriptLayoutManager.boxHeight + layout.imagePadding * 2)
    XCTAssertEqual(textView.string, "앞\n![](../images/gone.png)\n![](/Users/someone/a.png)\n뒤")
  }

  func testNonImageFileIsUnreadable() throws {
    try Data("그림 아님".utf8).write(to: project.imageFile(named: "note.png"))
    let (_, textView) = makeEditor("![](../images/note.png)")
    XCTAssertEqual(textView.manuscriptLayout!.images.status(of: entries(textView)[0].line), .unreadable)
  }

  func testThumbnailLoadsOffTheMainThreadAndIsSmall() {
    let (_, textView) = makeEditor()
    let images = textView.manuscriptLayout!.images!
    let loaded = expectation(description: "thumbnail")
    images.onLoaded = { if $0 == "wide.png" { loaded.fulfill() } }
    XCTAssertNil(images.thumbnail(fileName: "wide.png", maxPixel: 400))
    wait(for: [loaded], timeout: 5)
    let image = images.thumbnail(fileName: "wide.png", maxPixel: 400)
    XCTAssertNotNil(image)
    XCTAssertEqual(image?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 400)
  }

  func testPictureChangedOutsideIsReadAgain() throws {
    let (_, textView) = makeEditor()
    let layout = textView.manuscriptLayout!
    let tall = entries(textView)[1]
    XCTAssertEqual(layout.displaySize(of: tall.line).height, 700)
    try writePNG("tall.png", width: 400, height: 300)
    layout.revalidateImages()
    XCTAssertEqual(layout.displaySize(of: tall.line).height, 300)
    XCTAssertEqual(lineRect(textView, at: tall.range.location).height, 300 + layout.imagePadding * 2)
  }

  func testBreakingAndRestoringAnImageLineSwitchesBetweenTextAndPicture() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    let pictureHeight = lineRect(textView, at: wide.location).height
    textView.textStorage!.replaceCharacters(in: NSRange(location: NSMaxRange(wide), length: 0), with: "덧")
    XCTAssertEqual(entries(textView).count, 1)
    XCTAssertLessThan(lineRect(textView, at: wide.location).height, 80)
    textView.textStorage!.replaceCharacters(in: NSRange(location: NSMaxRange(wide), length: 1), with: "")
    XCTAssertEqual(entries(textView).count, 2)
    XCTAssertEqual(lineRect(textView, at: wide.location).height, pictureHeight)
  }

  /// A leading picture must not shift where blank-line numbers sit (they borrow the first text line's baseline).
  func testBlankLineNumbersIgnoreImageLines() {
    let (_, plain) = makeEditor("가\n\n나")
    let (_, withImage) = makeEditor("![](../images/wide.png)\n\n가")
    XCTAssertEqual(withImage.emptyLineBaselineFromTop, plain.emptyLineBaselineFromTop)
  }

  // MARK: - One block

  func testArrowsStepOverTheWholeLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: wide.location, length: 0))
    textView.moveRight(nil)
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(wide))
    textView.moveLeft(nil)
    XCTAssertEqual(textView.selectedRange().location, wide.location)
    textView.moveLeft(nil)
    XCTAssertEqual(textView.selectedRange().location, wide.location - 1)
  }

  func testUpDownLandOnAnEdge() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: 3, length: 0))
    textView.moveDown(nil)
    XCTAssertTrue([wide.location, NSMaxRange(wide)].contains(textView.selectedRange().location))
    textView.moveDown(nil)
    XCTAssertGreaterThan(textView.selectedRange().location, NSMaxRange(wide))
  }

  func testShiftSelectionTakesTheWholeLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: wide.location - 2, length: 0))
    for _ in 0..<3 { textView.moveRightAndModifySelection(nil) }
    XCTAssertEqual(textView.selectedRange(), NSRange(location: wide.location - 2, length: NSMaxRange(wide) - wide.location + 2))
  }

  func testClickOnPictureGoesToTheNearerEdge() {
    let (_, textView) = makeEditor()
    let layout = textView.manuscriptLayout!
    let wide = entries(textView)[0]
    let rect = layout.imageRect(for: wide).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    textView.setSelectedRange(NSRange(location: textView.characterIndexForInsertion(at: NSPoint(x: rect.minX + rect.width * 0.2, y: rect.midY)), length: 0))
    XCTAssertEqual(textView.selectedRange().location, wide.range.location)
    textView.setSelectedRange(NSRange(location: textView.characterIndexForInsertion(at: NSPoint(x: rect.minX + rect.width * 0.9, y: rect.midY)), length: 0))
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(wide.range))
  }

  func testCaretNeverRestsInsideAndRestoredPlaceSnaps() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: wide.location + 3, length: 0))
    XCTAssertEqual(textView.selectedRange().location, wide.location)
    textView.restoreViewState(EpisodeViewState(caret: NSMaxRange(wide) - 2, top: 0, openedAt: Date()))
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(wide))
  }

  func testPartialEditIsRefusedAndWholeLineEditAllowed() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    XCTAssertFalse(textView.shouldChangeText(in: NSRange(location: wide.location + 3, length: 2), replacementString: "x"))
    XCTAssertFalse(textView.shouldChangeText(in: NSRange(location: wide.location - 1, length: 3), replacementString: ""))
    XCTAssertEqual(textView.string, body)
    undoably(textView) { XCTAssertTrue(textView.shouldChangeText(in: wide, replacementString: "")) }
  }

  /// ⌥⌫/⌥⌦ never cut into the path; beside an image line they follow the ⌫/⌦ rules instead of doing nothing.
  func testWordDeleteBesideAnImageLineActsLikeDelete() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide), length: 0))
    undoably(textView) { textView.deleteWordBackward(nil) }
    XCTAssertFalse(textView.string.contains("wide.png"), "right after: the whole line goes")
    XCTAssertEqual(entries(textView).count, 1, "the other image line stays whole")

    textView.replaceAllText(with: body)
    textView.setSelectedRange(NSRange(location: wide.location, length: 0))
    undoably(textView) { textView.deleteWordForward(nil) }
    XCTAssertFalse(textView.string.contains("wide.png"), "right before: the whole line goes")

    textView.replaceAllText(with: body)
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide) + 1, length: 0))
    textView.deleteWordBackward(nil)
    XCTAssertEqual(textView.string, body, "start of the line below: nothing joins")
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(wide))

    textView.replaceAllText(with: body)
    textView.setSelectedRange(NSRange(location: wide.location - 1, length: 0))
    textView.deleteWordForward(nil)
    XCTAssertEqual(textView.string, body, "end of the line above: nothing joins")
  }

  func testDeleteAtTheStartOfTheLineBelowDoesNotJoinIt() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide) + 1, length: 0))
    textView.deleteBackward(nil)
    XCTAssertEqual(textView.string, body)
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(wide))
    XCTAssertEqual(entries(textView).count, 2)
    // A blank line below an image line is still removed.
    textView.replaceAllText(with: "앞\n![](../images/wide.png)\n\n뒤")
    textView.setSelectedRange(NSRange(location: NSMaxRange(entries(textView)[0].range) + 1, length: 0))
    undoably(textView) { textView.deleteBackward(nil) }
    XCTAssertEqual(textView.string, "앞\n![](../images/wide.png)\n뒤")
  }

  func testTabBesideAnImageLineGoesOnItsOwnLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide), length: 0))
    undoably(textView) { textView.insertTab(nil) }
    XCTAssertTrue(textView.string.contains("![](../images/wide.png)\n\t"))
    textView.replaceAllText(with: body)
    textView.setSelectedRange(NSRange(location: wide.location, length: 0))
    undoably(textView) { textView.insertTab(nil) }
    XCTAssertTrue(textView.string.contains("\t\n![](../images/wide.png)"))
    XCTAssertEqual(entries(textView).count, 2)
  }

  func testEnterBeforeTheMarkdownShowsThePicture() {
    let (_, textView) = makeEditor("글![](../images/wide.png)")
    textView.setSelectedRange(NSRange(location: 1, length: 0))
    undoably(textView) { textView.insertNewline(nil) }
    XCTAssertEqual(entries(textView).map(\.range), [NSRange(location: 2, length: 23)])
  }

  /// Scrolling through many pictures keeps only those near the screen decoded (PLAN ch.19 #4 memory).
  func testOnlyPicturesNearTheScreenStayDecoded() async throws {
    for index in 0..<12 { try writePNG("p\(index).png", width: 1600, height: 900) }
    let text = (0..<12).map { "문단 \($0)\n![](../images/p\($0).png)" }.joined(separator: "\n")
    let (scrollView, textView) = makeEditor(text)
    defer { withExtendedLifetime(scrollView) {} }
    let layout = textView.manuscriptLayout!
    for entry in entries(textView) {
      textView.scrollRangeToVisible(entry.range)
      guard case .project(let name) = entry.line.source else { continue }
      let rect = layout.imageRect(for: entry)
      let maxPixel = Int((max(rect.width, rect.height) * 2).rounded(.up))
      _ = layout.images.thumbnail(fileName: name, maxPixel: maxPixel)
      let end = ContinuousClock.now + .seconds(3)
      while layout.images.thumbnail(fileName: name, maxPixel: maxPixel) == nil, ContinuousClock.now < end {
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    XCTAssertLessThanOrEqual(layout.images.thumbnailCount, 6, "보이는 곳 ± 한 화면만")
    XCTAssertNotNil(layout.images.thumbnail(fileName: "p11.png", maxPixel: 1), "보고 있는 그림은 남는다")
  }

  // MARK: - Typing and deleting beside an image line

  /// The input method composes on the new line `keyDown` opened (a real keyboard can't be driven here; the real app check covers it).
  func testComposingAfterAnImageLineGoesOnANewLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide), length: 0))
    undoably(textView) {
      textView.openLineBesideImageLine(for: "ㅎ")
      textView.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
      textView.insertText("한", replacementRange: none)
    }
    XCTAssertTrue(textView.string.contains("![](../images/wide.png)\n한\n그림 뒤"))
    XCTAssertEqual(entries(textView).count, 2)
  }

  func testKeyBeforeAnImageLineOpensALineAboveBeforeTheInputMethod() throws {
    let (_, textView) = makeEditor()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = textView.enclosingScrollView
    window.makeFirstResponder(textView)
    let tall = entries(textView)[1].range
    textView.setSelectedRange(NSRange(location: tall.location, length: 0))
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
    undoably(textView) { textView.keyDown(with: event) }
    XCTAssertTrue(textView.string.contains("\n\na\n![](../images/tall.png)"), textView.string)
    XCTAssertEqual(entries(textView).count, 2)
  }

  func testDeleteRightAfterRemovesTheWholeLineAndUndoBringsItBack() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    let height = lineRect(textView, at: wide.location).height
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide), length: 0))
    undoably(textView) { textView.deleteBackward(nil) }
    XCTAssertFalse(textView.string.contains("wide.png"))
    XCTAssertEqual(entries(textView).count, 1)
    textView.undo(nil)
    XCTAssertEqual(textView.string, body)
    XCTAssertEqual(entries(textView).count, 2)
    XCTAssertEqual(lineRect(textView, at: wide.location).height, height)
  }

  func testDeleteRightBeforeOnlyMovesToThePreviousLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: wide.location, length: 0))
    textView.deleteBackward(nil)
    XCTAssertEqual(textView.string, body)
    XCTAssertEqual(textView.selectedRange().location, wide.location - 1)
  }

  func testDeleteBeforeAnImageLineAfterABlankLineRemovesTheBlankLine() {
    let (_, textView) = makeEditor()
    let tall = entries(textView)[1].range
    textView.setSelectedRange(NSRange(location: tall.location, length: 0))
    undoably(textView) { textView.deleteBackward(nil) }
    XCTAssertTrue(textView.string.contains("그림 뒤 줄이다.\n![](../images/tall.png)"))
    XCTAssertEqual(entries(textView).count, 2)
  }

  func testForwardDeleteBeforeAnImageLineRemovesItWhole() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: wide.location, length: 0))
    undoably(textView) { textView.deleteForward(nil) }
    XCTAssertFalse(textView.string.contains("wide.png"))
  }

  func testForwardDeleteDoesNotJoinTextAndImageLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    textView.setSelectedRange(NSRange(location: wide.location - 1, length: 0))
    textView.deleteForward(nil)
    XCTAssertEqual(textView.string, body)
    XCTAssertEqual(textView.selectedRange().location, wide.location)
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide), length: 0))
    textView.deleteForward(nil)
    XCTAssertEqual(textView.string, body)
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(wide) + 1)
  }

  /// Undo may restore a state that changes part of an image line (typing the closing parenthesis that made it one).
  func testUndoCanUnmakeAnImageLine() {
    let (_, textView) = makeEditor("앞\n![](../images/wide.png")
    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    undoably(textView) { textView.insertText(")", replacementRange: none) }
    XCTAssertEqual(entries(textView).count, 1)
    textView.undo(nil)
    XCTAssertEqual(textView.string, "앞\n![](../images/wide.png")
    XCTAssertTrue(entries(textView).isEmpty)
  }

  func testPasteAfterAnImageLineGoesOnANewLine() {
    let (_, textView) = makeEditor()
    let wide = entries(textView)[0].range
    let pasteboard = NSPasteboard.general
    let saved = pasteboard.string(forType: .string)
    defer {
      pasteboard.clearContents()
      if let saved { pasteboard.setString(saved, forType: .string) }
    }
    pasteboard.clearContents()
    pasteboard.setString("붙인 글", forType: .string)
    textView.setSelectedRange(NSRange(location: NSMaxRange(wide), length: 0))
    undoably(textView) { textView.paste(nil) }
    XCTAssertTrue(textView.string.contains("![](../images/wide.png)\n붙인 글\n"))
    XCTAssertEqual(entries(textView).count, 2)
  }
}
