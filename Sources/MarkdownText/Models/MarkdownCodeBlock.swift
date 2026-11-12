//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

/// A fenced/indented code node from the existing parsed Markdown tree.
/// Its identity is the same source-block identity used for native selection.
public struct MarkdownCodeBlock: Hashable, Sendable, Identifiable {
  public let id: String
  public let language: String?
  public let code: String

  public init(id: String, language: String?, code: String) {
    self.id = id
    self.language = language
    self.code = code
  }
}

/// Returning nil preserves the library's existing code renderer. View-only
/// customization does not replace parsing, document caching or source selection.
public typealias MarkdownCodeBlockRenderer = @MainActor @Sendable (MarkdownCodeBlock) -> AnyView?

private struct MarkdownCodeBlockRendererKey: EnvironmentKey {
  static let defaultValue: MarkdownCodeBlockRenderer? = nil
}

extension EnvironmentValues {
  public var markdownCodeBlockRenderer: MarkdownCodeBlockRenderer? {
    get { self[MarkdownCodeBlockRendererKey.self] }
    set { self[MarkdownCodeBlockRendererKey.self] = newValue }
  }
}

extension View {
  /// Render selected code languages at the AST's existing code-block boundary.
  public func markdownCodeBlockRenderer(_ renderer: @escaping MarkdownCodeBlockRenderer) -> some View {
    environment(\.markdownCodeBlockRenderer, renderer)
  }
}
