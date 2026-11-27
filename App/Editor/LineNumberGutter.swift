import AppKit
import NovelCore

/// 편집기 줄 번호.
///
/// - 줄 = 엔터마다(문단). 규칙은 비교 화면과 같은 `ParagraphLines`.
/// - 본문 칸(텍스트 컨테이너)의 자리·폭은 건드리지 않고 왼쪽 여백에 그림만 그린다. 켜고 꺼도 글자가 움직이지 않는다.
/// - 텍스트 저장소는 읽기만 한다. 조합 중에도 안전하다.
/// - 화면에 보이는 문단만 계산한다.
extension ManuscriptTextView {
  struct LineNumberPlacement: Equatable {
    let number: Int
    /// 번호 글자의 기준선 y(편집기 좌표, 위가 0)
    let baselineY: CGFloat
    /// 번호 칸 오른쪽 끝 x. 번호는 여기에 오른쪽 정렬한다.
    let rightX: CGFloat
  }

  static let lineNumberLeading: CGFloat = 20
  static let newline: unichar = 0x0A
  static func isLineBreak(_ character: unichar) -> Bool { character == 0x0A || character == 0x0D }
  static let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

  /// 가장 큰 번호 폭. 자릿수가 달라도 번호 끝이 맞게 이 폭에 오른쪽 정렬한다.
  var lineNumberColumnWidth: CGFloat {
    let digits = String(currentLineCount).count
    let sample = String(repeating: "0", count: digits) as NSString
    return ceil(sample.size(withAttributes: [.font: Self.lineNumberFont]).width)
  }

  /// 왼쪽 여백이 `번호 칸 + 40pt`보다 좁으면 번호만 숨긴다(본문을 밀지 않는다).
  var lineNumbersFit: Bool {
    textContainerInset.width >= lineNumberColumnWidth + Self.lineNumberLeading * 2
  }

  /// `rect`(편집기 좌표)에 걸치는 문단의 번호 자리. 그리기와 테스트가 같이 쓴다.
  func lineNumberPlacements(in rect: NSRect) -> [LineNumberPlacement] {
    guard showsLineNumbers, lineNumbersFit, let layoutManager, let textContainer, let storage = textStorage else {
      return []
    }
    let text = storage.mutableString
    let origin = textContainerOrigin
    let rightX = Self.lineNumberLeading + lineNumberColumnWidth
    var result: [LineNumberPlacement] = []

    if text.length > 0 {
      // 컨테이너 좌표로 옮겨 그 높이에 걸친 글리프만 고른다. 가로는 컨테이너 전체(번호 칸은 컨테이너 밖이라서).
      let probe = NSRect(x: 0, y: rect.minY - origin.y, width: textContainer.size.width, height: rect.height)
      let glyphs = layoutManager.glyphRange(forBoundingRect: probe, in: textContainer)
      let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
      if characters.location < text.length {
        var location = text.paragraphRange(for: NSRange(location: characters.location, length: 0)).location
        var number = ParagraphLines.lineBreaks(in: text, before: location) + 1
        let end = NSMaxRange(characters)
        let blankBaseline = emptyLineBaselineFromTop
        while location < text.length && location <= end {
          let glyph = layoutManager.glyphIndexForCharacter(at: location)
          let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
          // 빈 줄의 줄바꿈 글리프 자리는 글자 기준선보다 위에 잡혀서, 글자 줄과 같은 기준선을 쓴다.
          let isBlank = Self.isLineBreak(text.character(at: location))
          let baseline = origin.y + line.minY + (isBlank ? blankBaseline : layoutManager.location(forGlyphAt: glyph).y)
          if (!isBlank || numbersBlankLines), baseline - Self.lineNumberFont.ascender <= rect.maxY {
            result.append(LineNumberPlacement(number: number, baselineY: baseline, rightX: rightX))
          }
          location = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0)))
          number += 1
        }
      }
    }

    // 끝이 엔터면(또는 빈 회차면) 그 아래 빈 줄에도 커서를 둘 수 있으니 번호를 단다.
    let extra = layoutManager.extraLineFragmentRect
    if numbersBlankLines, !extra.isEmpty || text.length == 0 {
      let lineTop = origin.y + (extra.isEmpty ? 0 : extra.minY)
      let baseline = lineTop + emptyLineBaselineFromTop
      let lineHeight = max(extra.height, style.lineHeight)
      if lineTop <= rect.maxY && lineTop + lineHeight >= rect.minY {
        result.append(LineNumberPlacement(number: currentLineCount, baselineY: baseline, rightX: rightX))
      }
    }
    return result
  }

  /// 빈 줄(글리프가 없는 줄)의 기준선이 줄 위에서 얼마나 내려오는지. 줄 높이를 고정해서 모든 줄이 같다.
  /// 본문의 첫 글자(줄바꿈이 아닌 것)의 실제 값을 쓰고, 글자가 없을 때만 식으로 구한다. 식은 실제 값과 0.1pt쯤 다르다.
  var emptyLineBaselineFromTop: CGFloat {
    if let layoutManager, let storage = textStorage {
      let first = storage.mutableString.rangeOfCharacter(from: CharacterSet.newlines.inverted)
      if first.location != NSNotFound {
        return layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: first.location)).y
      }
    }
    let font = style.font
    return style.lineHeight + font.descender - style.baselineOffset
  }

  func drawLineNumbers(in rect: NSRect) {
    let placements = lineNumberPlacements(in: rect)
    guard !placements.isEmpty else { return }
    let font = Self.lineNumberFont
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.inkMuted]
    for placement in placements {
      let label = String(placement.number) as NSString
      let width = label.size(withAttributes: attributes).width
      // 편집기는 뒤집힌 좌표(위가 0)라 draw(at:)의 점은 글자 칸 위 왼쪽이다. 기준선에서 올림 값만큼 올린다.
      let point = NSPoint(x: placement.rightX - width, y: placement.baselineY - font.ascender)
      label.draw(at: point, withAttributes: attributes)
    }
  }
}
