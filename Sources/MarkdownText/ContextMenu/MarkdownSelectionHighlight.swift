import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// An exact selection in a particular unchanged rendered block.
public struct MarkdownSelectionHighlight: Hashable, Sendable {
  public let sourceBlockID: String
  public let renderedText: String
  public let range: NSRange
  public init(sourceBlockID: String, renderedText: String, range: NSRange) {
    self.sourceBlockID = sourceBlockID
    self.renderedText = renderedText
    self.range = range
  }
}

#if canImport(UIKit)
extension MarkdownSelectionHighlight {
  static func apply(_ highlight: Self?, to contents: NSMutableAttributedString, sourceBlockID: String?, document: NSAttributedString?) {
    guard let highlight, highlight.range.location != NSNotFound, highlight.range.location >= 0,
          highlight.range.length > 0, highlight.range.location <= (highlight.renderedText as NSString).length,
          highlight.range.length <= (highlight.renderedText as NSString).length - highlight.range.location else { return }
    func mark(_ range: NSRange) {
      guard range.location >= 0, range.location <= contents.length, range.length > 0,
            range.length <= contents.length - range.location else { return }
      contents.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: range)
    }
    if highlight.sourceBlockID == sourceBlockID, highlight.renderedText == contents.string {
      mark(highlight.range)
      return
    }
    // Resolve old paragraph bookmarks and new document-wide quotes against
    // exact immutable source spans. Repeated words never guess an occurrence.
    let key = MarkdownSelectionDocument.sourceBlockKey
    contents.enumerateAttribute(key, in: NSRange(location: 0, length: contents.length)) { value, local, _ in
      guard let id = value as? String else { return }
      let text = contents.attributedSubstring(from: local).string
      if id == highlight.sourceBlockID, text == highlight.renderedText {
        mark(NSRange(location: local.location + highlight.range.location, length: highlight.range.length))
      } else if highlight.sourceBlockID == MarkdownSelectionDocument.documentID,
                let document, document.string == highlight.renderedText {
        document.enumerateAttribute(key, in: NSRange(location: 0, length: document.length)) { sourceID, source, _ in
          guard sourceID as? String == id, document.attributedSubstring(from: source).string == text else { return }
          let overlap = NSIntersectionRange(source, highlight.range)
          if overlap.length > 0 {
            mark(NSRange(location: local.location + overlap.location - source.location, length: overlap.length))
          }
        }
      }
    }
  }
}
#endif

private struct SelectionHighlightKey: EnvironmentKey {
  static let defaultValue: MarkdownSelectionHighlight? = nil
}
private struct SelectionBlockKey: EnvironmentKey {
  static let defaultValue: String? = nil
}
extension EnvironmentValues {
  var markdownSelectionHighlight: MarkdownSelectionHighlight? {
    get { self[SelectionHighlightKey.self] }
    set { self[SelectionHighlightKey.self] = newValue }
  }
  var markdownSelectionBlockID: String? {
    get { self[SelectionBlockKey.self] }
    set { self[SelectionBlockKey.self] = newValue }
  }
}
public extension View {
  func markdownSelectionHighlight(_ highlight: MarkdownSelectionHighlight?) -> some View {
    environment(\.markdownSelectionHighlight, highlight)
  }
}

private struct SelectionActivityKey: EnvironmentKey {
  static let defaultValue: (@MainActor @Sendable (UUID, Bool) -> Void)? = nil
}
extension EnvironmentValues {
  var markdownSelectionActivity: (@MainActor @Sendable (UUID, Bool) -> Void)? {
    get { self[SelectionActivityKey.self] }
    set { self[SelectionActivityKey.self] = newValue }
  }
}
public extension View {
  /// Lets the enclosing chat pause auto-follow/keyboard dismissal during selection.
  func markdownSelectionActivity(_ onChange: @escaping @MainActor @Sendable (UUID, Bool) -> Void) -> some View {
    environment(\.markdownSelectionActivity, onChange)
  }
}
