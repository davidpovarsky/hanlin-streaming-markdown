// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

#if canImport(UIKit)
import UIKit

/// Built alongside parsing, never while a user drags native selection handles.
/// The original attributed spans and source IDs survive joining paragraphs.
enum MarkdownSelectionDocument {
  static let sourceBlockKey = NSAttributedString.Key("HanlinMarkdownSourceBlock")
  static let documentID = "hanlin-document"

  static func build(_ blocks: [MarkdownRenderable], config: MarkdownRenderConfig)
    -> (groups: [MarkdownRenderable], document: MarkdownRenderable) {
    var groups: [MarkdownRenderable] = []
    var pending = NSMutableAttributedString(string: "")
    var firstID: String?
    let document = NSMutableAttributedString(string: "")

    func flush() {
      guard let id = firstID else { return }
      groups.append(.paragraph(id: "hanlin-continuous:\(id)", content: pending))
      pending = NSMutableAttributedString(string: "")
      firstID = nil
    }

    for block in blocks {
      if let prose = prose(block, config: config) {
        if firstID == nil { firstID = block.id }
        append(prose, to: pending, spacing: config.blockSpacing)
        append(prose, to: document, spacing: config.blockSpacing)
      } else {
        flush()
        groups.append(block)
        if let content = selectionContent(block, config: config) {
          append(content, to: document, spacing: config.blockSpacing)
        }
      }
    }
    flush()
    return (groups, .paragraph(id: documentID, content: document))
  }

  private static func append(_ content: NSAttributedString, to target: NSMutableAttributedString, spacing: CGFloat) {
    guard content.length > 0 else { return }
    if target.length > 0 {
      let last = target.length - 1
      let style = (target.attribute(.paragraphStyle, at: last, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
      style.paragraphSpacing = spacing
      let paragraph = (target.string as NSString).paragraphRange(for: NSRange(location: last, length: 1))
      target.addAttribute(.paragraphStyle, value: style, range: paragraph)
      target.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
    }
    target.append(content)
  }

  private static func marked(_ content: NSAttributedString, id: String, lineSpacing: CGFloat = 5) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: content)
    guard result.length > 0 else { return result }
    let range = NSRange(location: 0, length: result.length)
    result.addAttribute(sourceBlockKey, value: id, range: range)
    result.enumerateAttribute(.paragraphStyle, in: range) { value, span, _ in
      let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
      style.alignment = .natural
      style.lineSpacing = lineSpacing
      result.addAttribute(.paragraphStyle, value: style, range: span)
    }
    return result
  }

  private static func prose(_ block: MarkdownRenderable, config: MarkdownRenderConfig) -> NSMutableAttributedString? {
    switch block {
    case .paragraph(let id, let content):
      return marked(content, id: id)
    case .heading(let id, let level, let content):
      let result = marked(content, id: id, lineSpacing: 0)
      result.addAttribute(.accessibilityTextHeadingLevel, value: level, range: NSRange(location: 0, length: result.length))
      return result
    case .orderedList(_, let items):
      return list(items, ordered: true, level: 0, config: config)
    case .unorderedList(_, let items, let level):
      return list(items, ordered: false, level: level, config: config)
    // Quote containers keep their original divider/nesting renderer.
    case .blockQuote: return nil
    default:
      return nil
    }
  }

  private static func list(_ items: [MarkdownListItem], ordered: Bool, level: Int, config: MarkdownRenderConfig) -> NSMutableAttributedString? {
    let result = NSMutableAttributedString(string: "")
    for (index, item) in items.enumerated() {
      let itemText = NSMutableAttributedString(string: "")
      for child in item.children {
        guard let contents = prose(child, config: config) else { return nil }
        append(contents, to: itemText, spacing: 8)
      }
      guard itemText.length > 0 else { continue }
      let marker: String
      if let checkbox = item.checkbox { marker = checkbox == .checked ? "☑  " : "☐  " }
      else { marker = ordered ? "\(index + 1).  " : "•  " }
      let prefix = NSAttributedString(string: marker, attributes: [
        .font: (ordered ? config.orderedListStyle : config.paragraphStyle).textFonts.normal,
        .foregroundColor: UIColor((ordered ? config.orderedListStyle : config.paragraphStyle).textColor)
      ])
      itemText.insert(prefix, at: 0)
      let style = NSMutableParagraphStyle()
      style.alignment = .natural
      style.firstLineHeadIndent = CGFloat(level) * 12
      style.headIndent = style.firstLineHeadIndent + 24
      style.lineSpacing = 5
      // A list item may contain nested paragraphs. Preserve their own indentation.
      let first = (itemText.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
      itemText.addAttribute(.paragraphStyle, value: style, range: first)
      append(itemText, to: result, spacing: 8)
    }
    return result
  }

  private static func selectionContent(_ block: MarkdownRenderable, config: MarkdownRenderConfig) -> NSAttributedString? {
    if let prose = prose(block, config: config) { return prose }
    let content: String
    var font = config.paragraphStyle.textFonts.normal
    switch block {
    case .codeBlock(_, _, let code):
      content = code
      font = config.codeBlockConfig.codeTextFonts.normal
    case .latex(_, let latex): content = "\\[" + latex + "\\]"
    case .blockQuote(_, let quote):
      content = quoteText(quote.quoteType)
      font = config.blockQuoteStyle.textFonts.normal
    case .table(_, let headers, let rows, _):
      let result = NSMutableAttributedString(string: "")
      for row in [headers] + rows {
        if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
        for (index, cell) in row.enumerated() {
          if index > 0 { result.append(NSAttributedString(string: "\t")) }
          result.append(cell)
        }
      }
      return marked(result, id: block.id)
    case .image(_, let image): content = image.alt
    case .thematicBreak: content = "—"
    case .orderedList(_, let items), .unorderedList(_, let items, _):
      let result = NSMutableAttributedString(string: "")
      for item in items {
        for child in item.children {
          if let text = selectionContent(child, config: config) {
            append(text, to: result, spacing: config.blockSpacing)
          }
        }
      }
      return result
    default: return nil
    }
    return marked(NSAttributedString(string: content, attributes: [
      .font: font, .foregroundColor: UIColor(config.paragraphStyle.textColor)
    ]), id: block.id)
  }

  private static func quoteText(_ quote: BlockQuoteType) -> String {
    switch quote {
    case .text(let text): text
    case .nested(let items): items.map(quoteText).joined(separator: "\n")
    }
  }
}
#endif
