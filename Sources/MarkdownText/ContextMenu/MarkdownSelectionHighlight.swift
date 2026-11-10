import SwiftUI

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
