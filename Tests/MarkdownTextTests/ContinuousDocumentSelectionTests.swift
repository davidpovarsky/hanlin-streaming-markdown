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
    XCTAssertEqual(groups.count, 3)
    guard case .codeBlock = groups[1], case .paragraph(let id, let contents)? = document.selectionDocument else {
      return XCTFail("Original code renderer and complete selection snapshot must both exist")
    }
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
}
#endif
