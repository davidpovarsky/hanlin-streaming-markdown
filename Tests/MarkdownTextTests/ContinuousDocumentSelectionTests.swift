import XCTest
@testable import SwiftStreamingMarkdown
#if canImport(UIKit)
import UIKit

@MainActor
final class ContinuousDocumentSelectionTests: XCTestCase {
  private var config: MarkdownRenderConfig {
    .default.withTextSelectionConfig(value: .init(isEnabled: false, continuousSelection: true))
  }

  func testOneNativeSurfaceSpansHeadingsParagraphsAndLists() async throws {
    let document = await MarkdownParserImpl().parse(text: "# כותרת\n\nשלום 👋🏽 **עולם**.\n\nSecond paragraph.\n\n- one\n- two", config: config)
    let groups = try XCTUnwrap(document.selectionRenderables)
    XCTAssertEqual(groups.count, 1, "Ordinary prose must not create one UITextView per paragraph or list item")
    guard case .paragraph(let id, let contents) = groups[0] else { return XCTFail("Expected a native text group") }
    let start = (contents.string as NSString).range(of: "שלום").location
    let end = NSMaxRange((contents.string as NSString).range(of: "two"))
    let selection = MarkdownTextSelection(attributedText: contents, selectedRange: NSRange(location: start, length: end - start), sourceBlockID: id)
    XCTAssertEqual(selection.text, (contents.string as NSString).substring(with: NSRange(location: start, length: end - start)))
    XCTAssertTrue(selection.text.contains("Second paragraph."))
    XCTAssertTrue(selection.text.contains("•  one"))
    XCTAssertEqual(selection.sourceBlockID, id)
    XCTAssertEqual(contents.attribute(.accessibilityTextHeadingLevel, at: 0, effectiveRange: nil) as? Int, 1)
  }

  func testSingleBlockQuoteKeepsExactOriginalRangeAndRepeatedTextIdentity() async throws {
    let document = await MarkdownParserImpl().parse(text: "same words\n\nsame words", config: config)
    guard case .paragraph(let originalID, _) = document.renderables[1],
          case .paragraph(let groupID, let contents)? = try XCTUnwrap(document.selectionRenderables).first else {
      return XCTFail("Expected parsed paragraphs")
    }
    let range = (contents.string as NSString).range(of: "same words", options: .backwards)
    let selection = MarkdownTextSelection(attributedText: contents, selectedRange: range, sourceBlockID: groupID)
    XCTAssertEqual(selection.sourceBlockID, originalID)
    XCTAssertEqual(selection.range, NSRange(location: 0, length: 10))
    XCTAssertEqual(selection.renderedText, "same words")
    let highlighted = NSMutableAttributedString(attributedString: contents)
    MarkdownSelectionHighlight.apply(.init(sourceBlockID: originalID, renderedText: selection.renderedText, range: selection.range),
      to: highlighted, sourceBlockID: groupID, document: nil)
    XCTAssertNil(highlighted.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    XCTAssertNotNil(highlighted.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
  }

  func testRichBlocksKeepTheirRendererWhileFullDocumentSelectionIncludesCode() async throws {
    let document = await MarkdownParserImpl().parse(text: "Before\n\n```swift\nlet value = 42\n```\n\nAfter", config: config)
    let groups = try XCTUnwrap(document.selectionRenderables)
    XCTAssertEqual(groups.count, 1)
    guard case .paragraph(_, let inline) = groups[0],
          case .paragraph(let id, let contents)? = document.selectionDocument else {
      return XCTFail("Original code renderer and complete selection snapshot must both exist")
    }
    let attachmentRange = (inline.string as NSString).range(of: "\u{FFFC}")
    let attachment = try XCTUnwrap(inline.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil) as? MarkdownRichBlockAttachment)
    guard case .codeBlock = attachment.block else { return XCTFail("Keep the original code renderer in the native document") }
    let inlineQuote = MarkdownTextSelection(attributedText: inline,
      selectedRange: NSRange(location: 0, length: inline.length))
    XCTAssertEqual(inlineQuote.text, "Before\nlet value = 42\nAfter")
    let range = NSRange(location: 0, length: contents.length)
    let quote = MarkdownTextSelection(attributedText: contents, selectedRange: range, sourceBlockID: id)
    XCTAssertEqual(quote.text, "Before\nlet value = 42\nAfter")
    XCTAssertEqual(quote.sourceBlockID, MarkdownSelectionDocument.documentID)
    let codeRange = (contents.string as NSString).range(of: "let value")
    XCTAssertEqual((contents.attribute(.font, at: codeRange.location, effectiveRange: nil) as? UIFont)?.fontName,
                   config.codeBlockConfig.codeTextFonts.normal.fontName)
  }

  func testDocumentQuoteHighlightsEachExactVisibleSourceSpan() async throws {
    let document = await MarkdownParserImpl().parse(text: "Before\n\n```swift\nlet value = 42\n```\n\nAfter", config: config)
    guard case .paragraph(let id, let full)? = document.selectionDocument,
          case .paragraph(let groupID, let after)? = try XCTUnwrap(document.selectionRenderables).last else {
      return XCTFail("Expected selection surfaces")
    }
    let highlighted = NSMutableAttributedString(attributedString: after)
    MarkdownSelectionHighlight.apply(.init(sourceBlockID: id, renderedText: full.string,
      range: NSRange(location: 0, length: full.length)), to: highlighted, sourceBlockID: groupID, document: full)
    XCTAssertNotNil(highlighted.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    let edited = NSMutableAttributedString(attributedString: after)
    MarkdownSelectionHighlight.apply(.init(sourceBlockID: id, renderedText: "different document",
      range: NSRange(location: 0, length: 5)), to: edited, sourceBlockID: groupID, document: full)
    XCTAssertNil(edited.attribute(.backgroundColor, at: 0, effectiveRange: nil))
  }

  func testSelectionCrossesDividerBeforeNextHebrewParagraph() async throws {
    let source = "# תחבורה\n\n- **רכבת** — תחנת ירושלים\n- אוטובוס למרכז\n\n---\n\nעצה מעשית: המשך אל התחנה הבאה."
    let document = await MarkdownParserImpl().parse(text: source, config: config)
    let groups = try XCTUnwrap(document.selectionRenderables)
    XCTAssertEqual(groups.count, 1, "A thematic break must not end the native selection document")
    guard case .paragraph(let id, let contents) = groups[0] else { return XCTFail("Expected one native document") }
    let start = (contents.string as NSString).range(of: "רכבת").location
    let end = NSMaxRange((contents.string as NSString).range(of: "הבאה."))
    let quote = MarkdownTextSelection(attributedText: contents,
      selectedRange: NSRange(location: start, length: end - start), sourceBlockID: id)
    XCTAssertTrue(quote.text.hasPrefix("רכבת"))
    XCTAssertTrue(quote.text.hasSuffix("הבאה."))
    XCTAssertFalse(quote.text.contains("\u{FFFC}"))
    XCTAssertTrue(quote.text.contains("\n\nעצה מעשית"))
    XCTAssertEqual(quote.range, NSRange(location: start, length: end - start))
    XCTAssertEqual(quote.renderedText, contents.string, "Native positions are retained separately from copied attachment text")
  }

  func testStructuredModelPartsAndEmbeddedUIShareDocumentAndSourceNamespaces() async throws {
    let parser = MarkdownDocumentParser()
    let parts: [MarkdownDocumentPart] = [
      .init(id: "first", sourcePrefix: "hanlin-part:first:", markdown: "same words\n\n---"),
      .init(id: "surface"),
      .init(id: "second", sourcePrefix: "hanlin-part:second:", markdown: "same words\n\nAfter 👋🏽")
    ]
    let document = await parser.parse(parts: parts, config: config)
    let groups = try XCTUnwrap(document.selectionRenderables)
    XCTAssertEqual(groups.count, 1)
    guard case .paragraph(let id, let contents) = groups[0] else { return XCTFail("Expected one native document") }
    let range = (contents.string as NSString).range(of: "same words", options: .backwards)
    let quote = MarkdownTextSelection(attributedText: contents, selectedRange: range, sourceBlockID: id)
    XCTAssertTrue(try XCTUnwrap(quote.sourceBlockID).hasPrefix("hanlin-part:second:"))
    XCTAssertEqual(quote.range, NSRange(location: 0, length: 10))
    let all = MarkdownTextSelection(attributedText: contents,
      selectedRange: NSRange(location: 0, length: contents.length), sourceBlockID: id)
    XCTAssertTrue(all.text.hasSuffix("After 👋🏽"))
    XCTAssertFalse(all.text.contains("\u{FFFC}"))
    XCTAssertEqual(all.sourceBlockID, id)
    let invalid = await parser.parse(parts: parts + [parts[0]], config: config)
    XCTAssertEqual(invalid, .empty, "Duplicate host IDs cannot alias a different source range")
  }

  func testStableRichAttachmentDoesNotReplaceSelectedPrefixWhenTailStreams() async throws {
    let old = await MarkdownParserImpl().parse(text: "Before\n\n```swift\nlet value = 42\n```\n\nAfter", config: config)
    let new = await MarkdownParserImpl().parse(text: "Before\n\n```swift\nlet value = 42\n```\n\nAfter more", config: config)
    guard case .paragraph(_, let before)? = old.selectionRenderables?.first,
          case .paragraph(_, let after)? = new.selectionRenderables?.first else { return XCTFail("Expected document") }
    let attachment = (before.string as NSString).range(of: "\u{FFFC}")
    let edit = NativeTextEditPlan(old: before, new: after)
    XCTAssertGreaterThan(edit.replacedRange.location, attachment.location)
    XCTAssertTrue(edit.preserves(NSRange(location: 0, length: NSMaxRange(attachment))))
  }

}
#endif
