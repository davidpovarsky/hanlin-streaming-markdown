// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

import Foundation

/// Native UTF-16 positions remain the source of truth for selection/bookmarks.
/// Only the copied/saved text expands atomic attachment positions to their
/// exact text. No guessed Markdown offsets or repeated-text search is involved.
enum MarkdownSelectionText {
  struct Replacement {
    let range: NSRange
    let text: String
  }

  static func expand(_ rendered: String, range: NSRange, replacements: [Replacement]) -> String {
    let source = rendered as NSString
    guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
          range.location <= source.length else { return "" }
    let end = range.location + min(range.length, source.length - range.location)
    var cursor = range.location
    var result = ""
    for replacement in replacements.sorted(by: { $0.range.location < $1.range.location }) {
      let span = replacement.range
      // A native attachment is one complete selected position. Invalid,
      // overlapping or only partly selected substitutions cannot alter text.
      guard span.location >= cursor, span.length > 0, span.location <= end,
            span.length <= end - span.location else { continue }
      result += source.substring(with: NSRange(location: cursor, length: span.location - cursor))
      result += replacement.text
      cursor = span.location + span.length
    }
    result += source.substring(with: NSRange(location: cursor, length: end - cursor))
    return result
  }
}
