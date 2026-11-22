// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

import Foundation

/// Ordered, trusted content supplied by the host. Embedded views cannot be
/// created by a Markdown fence; the host must explicitly provide their IDs.
public struct MarkdownDocumentPart: Hashable, Sendable, Identifiable {
  public enum Content: Hashable, Sendable {
    case markdown(String)
    case embedded(selectionText: String)
  }

  public let id: String
  public let sourcePrefix: String
  public let content: Content

  public init(id: String, sourcePrefix: String, markdown: String) {
    self.id = id
    self.sourcePrefix = sourcePrefix
    self.content = .markdown(markdown)
  }

  public init(id: String, selectionText: String = "") {
    self.id = id
    self.sourcePrefix = ""
    self.content = .embedded(selectionText: selectionText)
  }

  /// Reject ambiguous source coordinates instead of silently reusing a block
  /// ID from another part. An empty prefix is valid for a single Markdown part.
  static func hasUniqueCoordinates(_ parts: [Self]) -> Bool {
    var ids = Set<String>()
    var prefixes = Set<String>()
    for part in parts {
      guard !part.id.isEmpty, ids.insert(part.id).inserted else { return false }
      if case .markdown = part.content {
        guard prefixes.insert(part.sourcePrefix).inserted else { return false }
      }
    }
    return true
  }
}
