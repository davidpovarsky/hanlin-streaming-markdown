// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

extension MarkdownRenderable {
  /// Keep the parser's exact stable ID, scoped to the original host part.
  func namespaced(_ prefix: String) -> Self {
    guard !prefix.isEmpty else { return self }
    switch self {
    case .paragraph(let id, let value): return .paragraph(id: prefix + id, content: value)
    case .heading(let id, let level, let value): return .heading(id: prefix + id, level: level, content: value)
    case .latex(let id, let value): return .latex(id: prefix + id, content: value)
    case .orderedList(let id, let items): return .orderedList(id: prefix + id, items: items.map { $0.namespaced(prefix) })
    case .unorderedList(let id, let items, let level):
      return .unorderedList(id: prefix + id, items: items.map { $0.namespaced(prefix) }, nestedLevel: level)
    case .codeBlock(let id, let language, let code): return .codeBlock(id: prefix + id, language: language, code: code)
    case .table(let id, let headers, let rows, let raw): return .table(id: prefix + id, headers: headers, rows: rows, rawMarkdown: raw)
    case .thematicBreak(let id): return .thematicBreak(id: prefix + id)
    case .blockQuote(let id, let item): return .blockQuote(id: prefix + id, item: item)
    case .image(let id, let data): return .image(id: prefix + id, data: data)
    case .embedded(let id, let text): return .embedded(id: prefix + id, selectionText: text)
    }
  }
}

private extension MarkdownListItem {
  func namespaced(_ prefix: String) -> Self {
    Self(children: children.map { $0.namespaced(prefix) }, startsWithBold: startsWithBold, checkbox: checkbox)
  }
}
