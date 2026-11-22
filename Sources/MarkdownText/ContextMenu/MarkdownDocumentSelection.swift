// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

#if canImport(UIKit)
import SwiftUI
import UIKit

extension EnvironmentValues {
  @Entry var markdownDocumentSelectionMode = false
  @Entry var markdownSelectionDocument: NSAttributedString? = nil
  @Entry var markdownSelectionChanged: (@MainActor (MarkdownTextSelection) -> Void)? = nil
  @Entry var markdownSelectAllRequest: Binding<Bool>? = nil
  @Entry var markdownLongPressPreview: (@MainActor (UIView, CGPoint) -> Void)? = nil
}

public extension View {
  /// A single, scrollable native selection surface for the entire parsed document.
  /// Headings, emphasis, links, list markers and code keep their attributed styles.
  func markdownDocumentSelectionMode(_ enabled: Bool = true) -> some View {
    environment(\.markdownDocumentSelectionMode, enabled)
  }

  func markdownSelectionChanged(_ action: (@MainActor (MarkdownTextSelection) -> Void)?) -> some View {
    environment(\.markdownSelectionChanged, action)
  }

  func markdownSelectAllRequest(_ request: Binding<Bool>?) -> some View {
    environment(\.markdownSelectAllRequest, request)
  }

  /// A separate, deliberate stationary hold. The renderer never changes UIKit's
  /// own selection recognizers or context-menu implementation.
  func markdownLongPressPreview(_ action: (@MainActor (UIView, CGPoint) -> Void)?) -> some View {
    environment(\.markdownLongPressPreview, action)
  }
}
#endif
