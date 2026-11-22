// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

import Foundation

/// Keep TextKit's unchanged prefix intact while a streamed tail grows or its
/// speculative Markdown styling changes. Ranges always respect graphemes.
struct NativeTextEditPlan {
  let replacedRange: NSRange
  let replacementRange: NSRange
  let unchangedTextPrefixLength: Int

  init(old: NSAttributedString, new: NSAttributedString) {
    let oldText = old.string as NSString
    let newText = new.string as NSString
    var textPrefix = 0
    for (left, right) in zip(old.string.utf16, new.string.utf16) {
      guard left == right else { break }
      textPrefix += 1
    }
    func boundary(_ index: Int) -> Int {
      var result = index
      for text in [oldText, newText] where index < text.length {
        result = min(result, text.rangeOfComposedCharacterSequence(at: index).location)
        // NSString treats CR and LF separately on some Foundation platforms;
        // together they are one line-break grapheme and must be edited together.
        if index > 0, text.character(at: index - 1) == 13, text.character(at: index) == 10 {
          result = min(result, index - 1)
        }
      }
      return result
    }
    textPrefix = boundary(textPrefix)
    unchangedTextPrefixLength = textPrefix
    var unchanged = 0
    while unchanged < textPrefix {
      var oldRun = NSRange()
      var newRun = NSRange()
      let oldAttributes = old.attributes(at: unchanged, effectiveRange: &oldRun)
      let newAttributes = new.attributes(at: unchanged, effectiveRange: &newRun)
      guard NSDictionary(dictionary: oldAttributes).isEqual(NSDictionary(dictionary: newAttributes)) else { break }
      unchanged = min(textPrefix, NSMaxRange(oldRun), NSMaxRange(newRun))
    }
    unchanged = boundary(unchanged)
    replacedRange = NSRange(location: unchanged, length: old.length - unchanged)
    replacementRange = NSRange(location: unchanged, length: new.length - unchanged)
  }

  func preserves(_ selection: NSRange) -> Bool {
    selection.location != NSNotFound && selection.location >= 0 && selection.length > 0
      && selection.location <= unchangedTextPrefixLength
      && selection.length <= unchangedTextPrefixLength - selection.location
  }
}
