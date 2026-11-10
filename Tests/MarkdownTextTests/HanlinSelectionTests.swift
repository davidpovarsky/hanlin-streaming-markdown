import XCTest
import Markdown
@testable import SwiftStreamingMarkdown
#if canImport(UIKit)
import UIKit
#endif

final class HanlinSelectionTests: XCTestCase {
  func testMathLeavesLiteralCodeAndCurrencyUntouched() {
    let source = #"`\(literal\)` and $5 versus $10, then $x^2$ and \(y\)."#
    let result = LaTexPreProcessorImpl().process(input: source)
    XCTAssertEqual(result, #"`\(literal\)` and $5 versus $10, then `\(x^2\)` and `\(y\)`."#)
    let fenced = "```swift\nlet example = #\"\\(not math\\)\"#\n$$not math$$\n```"
    XCTAssertEqual(LaTexPreProcessorImpl().process(input: fenced), fenced)
    let unfinished = "```python\n\\(still code\\)"
    XCTAssertEqual(LaTexPreProcessorImpl().process(input: unfinished), unfinished)
  }

  #if canImport(UIKit)
  @MainActor func testNativeSelectionExpandsWholeGraphemesAndClampsInvalidRanges() {
    let body = NSAttributedString(string: "שלום 👨‍👩‍👧‍👦 e\u{301} end")
    let emoji = (body.string as NSString).range(of: "👨‍👩‍👧‍👦")
    let selection = MarkdownTextSelection(attributedText: body, selectedRange: NSRange(location: emoji.location + 1, length: 1))
    XCTAssertEqual(selection.text, "👨‍👩‍👧‍👦")
    XCTAssertEqual(selection.range, emoji)
    XCTAssertEqual(MarkdownTextSelection(attributedText: body, selectedRange: NSRange(location: NSNotFound, length: 0)).text, "")
  }

  @MainActor func testAppendingStreamPreservesNativeSelection() {
    let view = ParagraphUIView(frame: .zero, textContainer: nil)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    let host = UIViewController()
    window.rootViewController = host
    host.view.addSubview(view)
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    view.setParagraphContents(NSMutableAttributedString(string: "שלום 👋🏽 selected"), animatedByWord: false)
    view.becomeFirstResponder()
    let range = (view.text as NSString).range(of: "👋🏽 selected")
    view.selectedRange = range
    view.setParagraphContents(NSMutableAttributedString(string: "שלום 👋🏽 selected more streamed text"), animatedByWord: false)
    XCTAssertEqual(view.selectedRange, range)
  }
  #endif
}
