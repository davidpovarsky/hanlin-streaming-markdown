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
