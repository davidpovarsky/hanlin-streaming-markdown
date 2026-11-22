import XCTest
@testable import SwiftStreamingMarkdown

final class MarkdownDocumentBoundaryTests: XCTestCase {
  func testRichAttachmentExpansionUsesNativeRangeWithoutLeakingPlaceholders() {
    let source = "שלום 👋🏽\n\u{FFFC}\nAfter\n\u{FFFC}\nEnd"
    let native = source as NSString
    let first = native.range(of: "\u{FFFC}")
    let last = native.range(of: "\u{FFFC}", options: .backwards)
    let output = MarkdownSelectionText.expand(source, range: NSRange(location: 0, length: native.length), replacements: [
      .init(range: first, text: "let value = 42"), .init(range: last, text: "column\tvalue\nA\tB")
    ])
    XCTAssertEqual(output, "שלום 👋🏽\nlet value = 42\nAfter\ncolumn\tvalue\nA\tB\nEnd")
    XCTAssertEqual(MarkdownSelectionText.expand(source, range: last, replacements: [.init(range: last, text: "A\tB")]), "A\tB")
  }

  func testAdjacentSourceScopesCannotCollideOrInventRichParts() {
    let first = MarkdownDocumentPart(id: "a", sourcePrefix: "hanlin-part:a:", markdown: "same")
    let second = MarkdownDocumentPart(id: "b", sourcePrefix: "hanlin-part:b:", markdown: "same")
    XCTAssertTrue(MarkdownDocumentPart.hasUniqueCoordinates([first, .init(id: "app"), second]))
    XCTAssertFalse(MarkdownDocumentPart.hasUniqueCoordinates([first, first]))
    XCTAssertFalse(MarkdownDocumentPart.hasUniqueCoordinates([first,
      .init(id: "other", sourcePrefix: "hanlin-part:a:", markdown: "changed")]))
  }
}
