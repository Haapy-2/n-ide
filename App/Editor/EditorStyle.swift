import AppKit

/// 편집 영역 모양 값 (DESIGN.md 3장). 설정 값으로 만드는 방법은 `EditorSettings.swift`.
struct EditorStyle: Equatable {
  var fontName = "Pretendard-Regular"
  var fontSize: CGFloat = 17
  /// 줄 간격 배수
  var lineSpacing: CGFloat = 1.75
  /// 문단 간격(줄 단위)
  var paragraphSpacing: CGFloat = 0.6
  /// 한 줄에 들어가는 한글 글자 수
  var lineWidthInCharacters: CGFloat = 40

  /// 첫 줄 위 여백. 72pt였다가 사용자 요청으로 반(2026-11-12).
  static let topInset: CGFloat = 36
  static let minimumSideInset: CGFloat = 32

  var font: NSFont {
    NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
  }

  /// 줄 높이를 고정해 글꼴마다 기본 줄 높이가 달라도 줄 간격이 흔들리지 않게 한다.
  var lineHeight: CGFloat { (fontSize * lineSpacing).rounded() }

  /// 한글 한 글자 폭을 1em(글자 크기)로 본다.
  var textWidth: CGFloat { lineWidthInCharacters * fontSize }

  var paragraphStyle: NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    style.paragraphSpacing = lineHeight * paragraphSpacing
    style.lineBreakStrategy = .hangulWordPriority
    return style
  }

  /// 고정한 줄 높이 안에서 글자가 아래로 붙지 않고 가운데쯤 오도록 올린다.
  var baselineOffset: CGFloat {
    let font = font
    return ((lineHeight - (font.ascender - font.descender)) / 2).rounded()
  }

  var textAttributes: [NSAttributedString.Key: Any] {
    [
      .font: font,
      .paragraphStyle: paragraphStyle,
      .baselineOffset: baselineOffset,
      .foregroundColor: NSColor.ink,
    ]
  }
}
