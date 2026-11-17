@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class CitationIconTests: XCTestCase {
  func testOriginalCitationInitializerFunctionTypeRemainsCompatible() {
    let initializer: (Bool, CitationCoder, MDFont, Color, Color) -> MarkdownRenderConfig.CitationConfig = MarkdownRenderConfig.CitationConfig.init
    let config = initializer(true, .default, MDFont.systemFont(ofSize: 12), .primary, .clear)
    XCTAssertTrue(config.iconsByCitationURL.isEmpty)
  }

  func testFormattingBuildersPreserveImagesCitationsAndSelection() {
    let images = ImageConfig(enabled: true, allowedImageTypes: [.remote(allowedDomains: ["example.com"])])
    let citations = MarkdownRenderConfig.CitationConfig(font: MDFont.systemFont(ofSize: 12),
      textColor: .primary, backgroundColor: .clear, iconsByCitationURL: ["scope": Data([1, 2])])
    let baseline = MarkdownRenderConfig.default
    let configured = baseline.withImageConfig(images).withCitationConfig(value: citations)
      .withShouldAnimateText(value: false).withBlockSpacing(value: 12)
      .withParagraphStyle(value: baseline.paragraphStyle).withHeadingStyle(value: baseline.headingStyle)
      .withOrderedListStyle(value: baseline.orderedListStyle).withBlockQuoteStyle(value: baseline.blockQuoteStyle)
      .withTableStyle(value: baseline.tableStyle).withInlineStyle(value: baseline.inlineStyle)
      .withCodeBlockConfig(value: baseline.codeBlockConfig).withTextContextMenu(value: nil)
      .withTextSelectionConfig(value: baseline.textSelectionConfig).withThematicBreakColor(value: .clear)
    XCTAssertEqual(configured.imageConfig, images)
    XCTAssertEqual(configured.citationConfig, citations)
    XCTAssertEqual(configured.textSelectionConfig, baseline.textSelectionConfig)
  }

  #if canImport(UIKit)
  @MainActor func testHostSuppliedIconRendersInsideTheOriginalCitationAttachmentInBothDirections() throws {
    let url = try XCTUnwrap(URL(string: "hanlin-citation://message/sentence-15"))
    let data = InlineAttachmentData(type: .citation, title: "example.com +1", accessibilityLabel: "Two sources", url: url)
    let icon = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
      UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    let png = try XCTUnwrap(icon.pngData())
    func attachment(_ images: [String: Data], rtl: Bool = false) throws -> InlineCitationAttachment {
      try XCTUnwrap(InlineCitationAttachment(citationData: data,
        citationConfig: .init(font: .systemFont(ofSize: 12), textColor: .primary, backgroundColor: .clear,
          iconsByCitationURL: images, iconOnTrailingEdge: rtl)))
    }
    let plain = try XCTUnwrap(attachment([:]).image)
    let leading = try XCTUnwrap(attachment([url.absoluteString: png]).image)
    let trailing = try XCTUnwrap(attachment([url.absoluteString: png], rtl: true).image)
    XCTAssertGreaterThan(leading.size.width, plain.size.width)
    XCTAssertEqual(leading.size, trailing.size)
    XCTAssertNotEqual(leading.pngData(), trailing.pngData())
    XCTAssertEqual(try attachment(["another-message": png]).image?.size, plain.size)
    XCTAssertEqual(try attachment([url.absoluteString: Data([0, 1])]).image?.size, plain.size)
  }
  #endif
}
