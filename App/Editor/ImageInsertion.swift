import AppKit
import NovelCore

/// Putting pictures into the manuscript (PLAN ch.19 #1, 14-1 ③b): menu, Finder drop, paste, and the broken-box menu.
/// Files are written first, off the main thread, and only then does a line point at them (G10). Lines go in after
/// Hangul composition ends (G9) as one undo unit. Undo removes the line but never the file (G2).
extension ManuscriptTextView {
  static func sendInsertImage() {
    NSApp.sendAction(#selector(insertImageFromPanel(_:)), to: nil, from: nil)
  }

  @objc func insertImageFromPanel(_ sender: Any?) {
    finishComposition()
    guard project != nil else { return }
    let urls = SystemDialogs.askImages(multiple: true)
    guard !urls.isEmpty else { return }
    insertImages(urls.map(ImageSource.file))
  }

  /// Lines go where the selection is once the files are written. If the episode changed meanwhile, the files and names stay
  /// (they show as unused pictures) and no line goes in.
  func insertImages(_ sources: [ImageSource]) {
    finishComposition()
    dropMultiCursor()
    importImages(sources) { view, imported in
      view.replaceForImages(view.selectedRange(), fileNames: imported.map(\.fileName), actionName: "그림 넣기")
    }
  }

  // MARK: - Drop

  /// Picture files or data dropped on the editor go in at the drop point. False to let the text view handle the drop.
  func dropImages(_ info: NSDraggingInfo) -> Bool {
    guard project != nil, let sources = ImageImporter.sources(on: info.draggingPasteboard) else { return false }
    let point = convert(info.draggingLocation, from: nil)
    window?.makeFirstResponder(self)
    finishComposition()
    setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
    insertImages(sources)
    return true
  }

  // MARK: - Broken box

  /// Right-click on a picture that can't be shown (G1·G4·G17): offer another picture, or copy an outside file into the project.
  func brokenImageMenuItems(at point: NSPoint) -> [NSMenuItem] {
    guard let entry = imageEntry(at: point), let images = manuscriptLayout?.images else { return [] }
    if case .ready = images.status(of: entry.line) { return [] }
    let line = (string as NSString).substring(with: entry.range)
    var items: [NSMenuItem] = []
    let replace = NSMenuItem(title: "다른 그림으로 바꾸기…", action: #selector(replaceBrokenImage(_:)), keyEquivalent: "")
    replace.representedObject = ImageLineTarget(range: entry.range, text: line)
    replace.target = self
    items.append(replace)
    if case .outside(let path) = entry.line.source, let file = outsideImageFile(path) {
      let adopt = NSMenuItem(title: "작품에 넣기", action: #selector(adoptOutsideImage(_:)), keyEquivalent: "")
      adopt.representedObject = ImageLineTarget(range: entry.range, text: line, file: file)
      adopt.target = self
      items.append(adopt)
    }
    return items
  }

  @objc private func replaceBrokenImage(_ sender: NSMenuItem) {
    guard let target = sender.representedObject as? ImageLineTarget,
      let url = SystemDialogs.askImages(multiple: false).first
    else { return }
    replaceImageLine(target, with: .file(url))
  }

  @objc private func adoptOutsideImage(_ sender: NSMenuItem) {
    guard let target = sender.representedObject as? ImageLineTarget, let file = target.file else { return }
    replaceImageLine(target, with: .file(file))
  }

  /// The line is swapped only if it still reads the same where it was, so text typed meanwhile is never overwritten.
  private func replaceImageLine(_ target: ImageLineTarget, with source: ImageSource) {
    finishComposition()
    dropMultiCursor()
    importImages([source]) { view, imported in
      let text = view.string as NSString
      guard NSMaxRange(target.range) <= text.length, text.substring(with: target.range) == target.text,
        let fileName = imported.first?.fileName
      else {
        view.onNotice("그림 줄이 바뀌어서 바꾸지 않았어요. 새 그림은 작품에 남아 있어요.")
        return
      }
      view.replaceForImages(target.range, fileNames: [fileName], actionName: "그림 바꾸기")
    }
  }

  private func imageEntry(at point: NSPoint) -> ImageLineIndex.Entry? {
    guard let manager = manuscriptLayout, let container = textContainer, !manager.imageLines.entries.isEmpty else { return nil }
    let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    let glyph = manager.glyphIndex(for: local, in: container)
    let character = manager.characterIndexForGlyph(at: glyph)
    guard let entry = manager.imageLines.entry(containing: character) ?? manager.imageLines.entry(endingAt: character),
      manager.imageRect(for: entry).contains(local)
    else { return nil }
    return entry
  }

  private func outsideImageFile(_ path: String) -> URL? {
    guard let project, let file = ImageImport.outsideFile(path, episodesFolder: project.episodesFolder),
      ImageImporter.isImageFile(file)
    else { return nil }
    return file
  }

  // MARK: - Shared steps

  private func importImages(_ sources: [ImageSource], then place: @escaping (ManuscriptTextView, [ImageImporter.Imported]) -> Void) {
    guard let layout = project, !sources.isEmpty else { return }
    let store = ProjectStore(root: layout.root)
    let generation = textGeneration
    imageInsertsInFlight += 1
    Task { [weak self] in
      defer { self?.imageInsertsInFlight -= 1 }
      let results = await Task.detached(priority: .userInitiated) {
        sources.map { source in Result { () throws(ImageImporter.Failure) in try ImageImporter.write(source, to: store) } }
      }.value
      guard let self else { return }
      let imported = results.compactMap { try? $0.get() }
      if let notice = Self.failureNotice(results) { onNotice(notice) }
      guard !imported.isEmpty else { return }
      onImagesAdded(imported.map(\.meta))
      // Nothing ends composition when the window closes; stop waiting then instead of holding the editor forever.
      while hasMarkedText() {
        guard window != nil else { return }
        try? await Task.sleep(for: .milliseconds(50))
      }
      guard textGeneration == generation, project?.root == layout.root else { return }
      place(self, imported)
    }
  }

  private static func failureNotice(_ results: [Result<ImageImporter.Imported, ImageImporter.Failure>]) -> String? {
    let failures = results.compactMap { result -> ImageImporter.Failure? in
      if case .failure(let failure) = result { return failure }
      return nil
    }
    guard let first = failures.first else { return nil }
    let some = failures.count < results.count ? "그림 \(failures.count)개는 " : "그림을 "
    switch first {
    case .unreadable: return some + "읽지 못해 넣지 않았어요. 그림 파일이 아니거나 iCloud에서 아직 내려받지 않았을 수 있어요."
    case .writeFailed(let reason): return some + "작품 폴더에 저장하지 못했어요. \(reason)"
    }
  }

  private func replaceForImages(_ range: NSRange, fileNames: [String], actionName: String) {
    guard NSMaxRange(range) <= (string as NSString).length else { return }
    let plan = ImageImport.insertion(fileNames: fileNames, in: string as NSString, replacing: range)
    let undo = episodeUndoManager
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    guard shouldChangeText(in: range, replacementString: plan.text) else { return }
    forgetInputInProgress()
    textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: plan.text, attributes: style.textAttributes))
    didChangeText()
    undo.setActionName(actionName)
    setSelectedRange(NSRange(location: plan.caret, length: 0))
    scrollRangeToVisible(selectedRange())
  }
}

/// The image line a broken-box menu item acts on, as it read when the menu opened.
private final class ImageLineTarget: NSObject {
  let range: NSRange
  let text: String
  let file: URL?

  init(range: NSRange, text: String, file: URL? = nil) {
    self.range = range
    self.text = text
    self.file = file
    super.init()
  }
}
