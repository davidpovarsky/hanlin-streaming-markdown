import Foundation

@main
struct CrossBlockSelectionChecks {
  static func main() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ description: String) {
      checks += 1
      precondition(condition(), "Cross-block selection failure: \(description)")
    }
    func expanded(_ source: String, _ range: NSRange, _ replacements: [MarkdownSelectionText.Replacement]) -> String {
      MarkdownSelectionText.expand(source, range: range, replacements: replacements)
    }
    let cases: [(String, String, String)] = [
      ("שלום 👋🏽", "עצה מעשית", ""),
      ("Before", "After", "let value = 42"),
      ("לפני", "بعد", "A\tB\n1\t2"),
      ("e\u{301}", "👩🏽‍💻", "\\[x^2\\]"),
      ("line\r\nnext", "tail", "quote\ncontinuation")
    ]
    for (before, after, payload) in cases {
      let native = before + "\n\u{FFFC}\n" + after
      let source = native as NSString
      let attachment = source.range(of: "\u{FFFC}")
      let replacements = [MarkdownSelectionText.Replacement(range: attachment, text: payload)]
      check(expanded(native, NSRange(location: 0, length: source.length), replacements) == before + "\n" + payload + "\n" + after,
        "full native selection expands exact payload across \(before.debugDescription) → \(after.debugDescription)")
      check(expanded(native, attachment, replacements) == payload, "one selected rich position")
      check(expanded(native, NSRange(location: 0, length: attachment.location), replacements) == before + "\n", "selection before attachment excludes it")
      let start = NSMaxRange(attachment)
      check(expanded(native, NSRange(location: start, length: source.length - start), replacements) == "\n" + after, "selection after attachment excludes it")
      check(expanded(native, NSRange(location: source.length, length: 0), replacements).isEmpty, "empty end selection")
    }
    let native = "first\n\u{FFFC}\nsecond\n\u{FFFC}\nthird"
    let source = native as NSString
    let first = source.range(of: "\u{FFFC}")
    let last = source.range(of: "\u{FFFC}", options: .backwards)
    let replacements = [MarkdownSelectionText.Replacement(range: last, text: "code\nvalue"), .init(range: first, text: "")]
    check(expanded(native, NSRange(location: 0, length: source.length), replacements) == "first\n\nsecond\ncode\nvalue\nthird", "multiple rich positions preserve stream order")
    check(expanded(native, NSRange(location: first.location, length: NSMaxRange(last) - first.location), replacements) == "\nsecond\ncode\nvalue", "range starts and ends on rich positions")
    check(expanded(native, NSRange(location: NSNotFound, length: 1), replacements).isEmpty, "invalid NSNotFound selection")
    check(expanded(native, NSRange(location: -1, length: 2), replacements).isEmpty, "negative native selection")
    check(expanded(native, NSRange(location: source.length + 1, length: 1), replacements).isEmpty, "out-of-document selection")
    check(expanded("abc", NSRange(location: 1, length: Int.max), []) == "bc", "oversized range is bounded without overflow")
    check(expanded("abc", NSRange(location: 0, length: 3), [.init(range: NSRange(location: -1, length: 1), text: "x")]) == "abc", "invalid attachment offset cannot rewrite text")
    check(expanded("abc", NSRange(location: 0, length: 3), [.init(range: NSRange(location: 1, length: Int.max), text: "x")]) == "abc", "invalid attachment length cannot overflow")
    check(expanded("abc", NSRange(location: 1, length: 1), [.init(range: NSRange(location: 0, length: 2), text: "x")]) == "b", "partial replacement leaves exact selected native text")
    let a = MarkdownDocumentPart(id: "a", sourcePrefix: "hanlin-part:a:", markdown: "same")
    let b = MarkdownDocumentPart(id: "b", sourcePrefix: "hanlin-part:b:", markdown: "same")
    check(MarkdownDocumentPart.hasUniqueCoordinates([a, .init(id: "surface"), b]), "repeated prose in separate parts has distinct coordinates")
    check(!MarkdownDocumentPart.hasUniqueCoordinates([a, a]), "duplicate host ID fails closed")
    check(!MarkdownDocumentPart.hasUniqueCoordinates([a, .init(id: "b", sourcePrefix: "hanlin-part:a:", markdown: "different")]), "duplicate source namespace fails closed")
    check(!MarkdownDocumentPart.hasUniqueCoordinates([.init(id: "")]), "empty rich ID fails closed")
    check(MarkdownDocumentPart.hasUniqueCoordinates([.init(id: "answer", sourcePrefix: "", markdown: "original")]), "original unsplit paragraph retains source IDs")
    check(!MarkdownDocumentPart.hasUniqueCoordinates([.init(id: "a", sourcePrefix: "", markdown: "a"), .init(id: "b", sourcePrefix: "", markdown: "b")]), "separate unscoped fragments cannot collide")
    if case .markdown = MarkdownDocumentPart(id: "prose", sourcePrefix: "", markdown: "```openui-lang\nuntrusted\n```").content {
      check(true, "Markdown syntax alone cannot construct trusted embedded document parts")
    } else { check(false, "untrusted Markdown fence became embedded part") }
    print("PASS cross-block-selection-domain \(checks) checks; Foundation only, no UIKit runtime claim")
  }
}
