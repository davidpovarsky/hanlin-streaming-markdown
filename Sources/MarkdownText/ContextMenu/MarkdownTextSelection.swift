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
    let location = selectedRange.location == NSNotFound ? 0 : min(max(0, selectedRange.location), attributedText.length)
    let clamped = NSRange(location: location, length: min(max(0, selectedRange.length), attributedText.length - location))
    let range = clamped.length == 0 ? clamped : (attributedText.string as NSString).rangeOfComposedCharacterSequences(for: clamped)
    // A quote contained in one original block keeps its established source ID
    // and local offsets. A quote crossing blocks uses the joined document range.
    var sourceRange = NSRange(location: 0, length: attributedText.length)
    let block = range.length > 0 ? attributedText.attribute(
      MarkdownSelectionDocument.sourceBlockKey, at: range.location,
      longestEffectiveRange: &sourceRange, in: NSRange(location: 0, length: attributedText.length)
    ) as? String : nil
    if let block, NSIntersectionRange(sourceRange, range) == range {
      self.sourceBlockID = block
      self.range = NSRange(location: range.location - sourceRange.location, length: range.length)
      self.renderedText = attributedText.attributedSubstring(from: sourceRange).string
    } else {
      self.sourceBlockID = sourceBlockID
      self.range = range
      self.renderedText = attributedText.string
    }
    self.text = Self.expandedText(attributedText, range: range)
  }

  static func expandedText(_ contents: NSAttributedString, range: NSRange? = nil) -> String {
    let selectedRange = range ?? NSRange(location: 0, length: contents.length)
    var replacements: [MarkdownSelectionText.Replacement] = []
    contents.enumerateAttribute(.attachment, in: selectedRange) { value, span, _ in
      let text: String?
      if let attachment = value as? MarkdownRichBlockAttachment {
        text = attachment.selectionText
      } else if let attachment = value as? InlineCitationAttachment, let citation = attachment.citationData {
        text = citation.title
      } else if let attachment = value as? NSTextAttachment,
                let data = attachment.contents,
                let math = try? JSONDecoder().decode(LatexAttachmentData.self, from: data) {
        text = "\\(" + math.latex + "\\)"
      } else { text = nil }
      if let text { replacements.append(.init(range: span, text: text)) }
    }
    return MarkdownSelectionText.expand(contents.string, range: selectedRange, replacements: replacements)
  }

  #endif
}
