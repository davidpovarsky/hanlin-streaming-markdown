// Copyright (c) 2026 Hanlin contributors.
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The native rendered-text range, retained separately from the Markdown source.
/// Consumers can save an exact excerpt without treating a rendered offset as a source offset.
public struct MarkdownTextSelection: Sendable {
  public let sourceBlockID: String?
  public let text: String
  public let renderedText: String
  public let range: NSRange

  #if canImport(UIKit)
  public init(attributedText: NSAttributedString, selectedRange: NSRange, sourceBlockID: String? = nil) {
    self.sourceBlockID = sourceBlockID
    let location = selectedRange.location == NSNotFound ? 0 : min(max(0, selectedRange.location), attributedText.length)
    let clamped = NSRange(location: location, length: min(max(0, selectedRange.length), attributedText.length - location))
    let range = clamped.length == 0 ? clamped : (attributedText.string as NSString).rangeOfComposedCharacterSequences(for: clamped)
    self.range = range
    self.renderedText = attributedText.string
    let selected = attributedText.attributedSubstring(from: range)
    var text = ""
    selected.enumerateAttributes(in: NSRange(location: 0, length: selected.length)) { attributes, range, _ in
      if let attachment = attributes[.attachment] as? NSTextAttachment,
         let contents = attachment.contents,
         let math = try? JSONDecoder().decode(LatexAttachmentData.self, from: contents) {
        text += "\\(" + math.latex + "\\)"
      } else {
        text += selected.attributedSubstring(from: range).string
      }
    }
    self.text = text
  }
  #endif
}
