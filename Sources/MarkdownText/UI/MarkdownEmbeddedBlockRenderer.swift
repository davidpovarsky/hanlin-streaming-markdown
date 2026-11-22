// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

import SwiftUI

/// Renders an explicitly supplied embedded document part. The identifier comes
/// from MarkdownDocumentPart, never from model-authored Markdown syntax.
public typealias MarkdownEmbeddedBlockRenderer = @MainActor @Sendable (String) -> AnyView?

extension EnvironmentValues {
  @Entry var markdownEmbeddedBlockRenderer: MarkdownEmbeddedBlockRenderer? = nil
  @Entry var markdownIsRichAttachment = false
}

public extension View {
  func markdownEmbeddedBlockRenderer(_ renderer: MarkdownEmbeddedBlockRenderer?) -> some View {
    environment(\.markdownEmbeddedBlockRenderer, renderer)
  }
}
