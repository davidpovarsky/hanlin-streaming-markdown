//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown

extension RenderableDocument {
  /// Boundary metadata for already parsed code nodes; never discovers or splits
  /// Markdown blocks. Source ranges belong to the preprocessed parser input.
  static func fenceClosure(in document: Document, source: String) -> [String: Bool] {
    let lines = source.components(separatedBy: "\n")
    var result: [String: Bool] = [:]
    func visit(_ node: Markup) {
      if let block = node as? Markdown.CodeBlock, let range = block.range {
        result[block.id] = hasClosingFence(block, range: range)
      }
      for child in node.children { visit(child) }
    }
    func normalizedBoundary(_ line: String) -> String {
      var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      while value.hasPrefix(">") {
        value.removeFirst()
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return value
    }
    func hasClosingFence(_ block: Markdown.CodeBlock, range: SourceRange) -> Bool {
      guard range.lowerBound.line > 0, range.upperBound.line > range.lowerBound.line,
            range.upperBound.line <= lines.count else { return false }
      let openingLine = lines[range.lowerBound.line - 1]
      guard let openingRange = openingLine.range(of: "`{3,}|~{3,}", options: .regularExpression) else { return false }
      let opening = openingLine[openingRange]
      let closing = normalizedBoundary(lines[range.upperBound.line - 1])
      guard let character = opening.first, closing.count >= opening.count,
            closing.allSatisfy({ $0 == character }) else { return false }
      // If the delimiter remains in the parsed literal code, cmark did not
      // consume it as a closing fence (e.g. four-space-indented partial input).
      // Ambiguous literal-delimiter endings conservatively remain source code.
      let lastLiteralLine = block.code.components(separatedBy: "\n")
        .last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
      return normalizedBoundary(lastLiteralLine) != closing
    }
    visit(document)
    return result
  }
}
