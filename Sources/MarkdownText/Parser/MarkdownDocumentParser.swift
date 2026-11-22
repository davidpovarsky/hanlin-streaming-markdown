// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

/// One parser/cache per mounted MarkdownView. The cache contains only the
/// current part IDs, so streaming a tail does not reparse completed rich parts.
actor MarkdownDocumentParser {
  private struct Entry {
    let part: MarkdownDocumentPart
    let config: MarkdownRenderConfig
    let document: RenderableDocument
  }
  private var entries: [String: Entry] = [:]

  func parse(parts: [MarkdownDocumentPart], config: MarkdownRenderConfig) async -> RenderableDocument {
    guard MarkdownDocumentPart.hasUniqueCoordinates(parts) else { return .empty }
    var nextEntries: [String: Entry] = [:]
    var blocks: [MarkdownRenderable] = []
    var fences: [String: Bool] = [:]
    let selection = config.textSelectionConfig
    let parseConfig = config.withTextSelectionConfig(value: .init(isEnabled: selection.isEnabled,
      backgroundColor: selection.backgroundColor, continuousSelection: false))
    for part in parts {
      guard !Task.isCancelled else { return .empty }
      switch part.content {
      case .markdown(let text):
        let document: RenderableDocument
        if let entry = entries[part.id], entry.part == part, entry.config == parseConfig {
          document = entry.document
        } else {
          document = await MarkdownParserImpl().parse(text: text, config: parseConfig)
        }
        nextEntries[part.id] = Entry(part: part, config: parseConfig, document: document)
        blocks.append(contentsOf: document.renderables.map { $0.namespaced(part.sourcePrefix) })
        for (id, closed) in document.codeBlockFenceClosure { fences[part.sourcePrefix + id] = closed }
      case .embedded(let text):
        blocks.append(.embedded(id: part.id, selectionText: text))
      }
    }
    guard !Task.isCancelled else { return .empty }
    entries = nextEntries
    return RenderableDocument(renderables: blocks, fenceClosure: fences, config: config)
  }
}
