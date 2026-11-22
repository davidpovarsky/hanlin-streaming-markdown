import Foundation

@main
struct VerifyNativeTextEditPlan {
  static func main() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
      precondition(condition(), message)
      checks += 1
    }
    let style = NSAttributedString.Key("test-style")
    func verify(_ old: NSAttributedString, _ new: NSAttributedString, expectedStart: Int? = nil) -> NativeTextEditPlan {
      let edit = NativeTextEditPlan(old: old, new: new)
      let result = NSMutableAttributedString(attributedString: old)
      result.replaceCharacters(in: edit.replacedRange, with: new.attributedSubstring(from: edit.replacementRange))
      check(result.isEqual(to: new), "Tail replacement must exactly reproduce both text and attributes")
      if let expectedStart {
        check(edit.replacedRange.location == expectedStart,
          "Unchanged prefix expected \(expectedStart), got \(edit.replacedRange.location); old UTF16 \(Array(old.string.utf16)), new UTF16 \(Array(new.string.utf16))")
      }
      return edit
    }
    let old = NSAttributedString(string: "שלום\nSecond paragraph", attributes: [style: "body"])
    let append = NSAttributedString(string: old.string + " more", attributes: [style: "body"])
    let edit = verify(old, append, expectedStart: old.length)
    check(edit.preserves(NSRange(location: 0, length: old.length)), "Cross-paragraph selection must survive append")
    check(!edit.preserves(NSRange(location: NSNotFound, length: 1)), "Invalid selection must not be restored")
    let restyled = NSMutableAttributedString(attributedString: append)
    let bold = (restyled.string as NSString).range(of: "paragraph")
    restyled.addAttribute(style, value: "bold", range: bold)
    let styleEdit = verify(append, restyled, expectedStart: bold.location)
    check(styleEdit.preserves(NSRange(location: 0, length: append.length)), "Attribute changes must preserve a stable text selection")
    for (before, after) in [("e", "e\u{301}"), ("👨", "👨‍👩‍👧‍👦"), ("👍", "👍🏽"), ("\r", "\r\n")] {
      let old = NSAttributedString(string: before)
      let edit = verify(old, NSAttributedString(string: after), expectedStart: 0)
      check(!edit.preserves(NSRange(location: 0, length: old.length)), "A changed grapheme must not retain a partial selection")
    }
    _ = verify(NSAttributedString(string: "\r\n"), NSAttributedString(string: "\r"), expectedStart: 0)
    let newline = NSAttributedString(string: "\r\n", attributes: [style: "body"])
    let restyledNewline = NSMutableAttributedString(attributedString: newline)
    restyledNewline.addAttribute(style, value: "changed", range: NSRange(location: 1, length: 1))
    _ = verify(newline, restyledNewline, expectedStart: 0)
    _ = verify(NSAttributedString(string: "before tail"), NSAttributedString(string: "before"), expectedStart: 6)
    _ = verify(NSAttributedString(string: "one"), NSAttributedString(string: "two"), expectedStart: 0)
    _ = verify(old, old, expectedStart: old.length)
    let long = String(repeating: "Stable paragraph with RTL עברית and emoji 👋🏽.\n", count: 200)
    var previous = NSAttributedString(string: long, attributes: [style: "unchanged"])
    for index in 0..<100 {
      let next = NSAttributedString(string: previous.string + " \(index)", attributes: [style: "unchanged"])
      let plan = verify(previous, next, expectedStart: previous.length)
      check(plan.replacedRange.length == 0, "An appended token must not remove the stable document prefix")
      previous = next
    }
    print("PASS: \(checks) native text edit-plan checks")
  }
}
