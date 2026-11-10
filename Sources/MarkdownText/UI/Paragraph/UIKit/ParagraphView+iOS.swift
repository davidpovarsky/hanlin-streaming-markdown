//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import SwiftUI

struct ParagraphView: UIViewRepresentable {
  @Environment(\.openURL) var openURL
  @Environment(\.markdownConfig) var config: MarkdownRenderConfig
  @Environment(\.markdownController) var markdownController: MarkdownController?

  @Environment(\.markdownSelectionBlockID) var sourceBlockID
  @Environment(\.markdownSelectionHighlight) var highlight

  private var displayedContents: NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: contents)
    if let highlight, highlight.sourceBlockID == sourceBlockID,
       highlight.renderedText == contents.string, highlight.range.location != NSNotFound,
       highlight.range.location >= 0, highlight.range.length > 0,
       highlight.range.location <= contents.length,
       highlight.range.length <= contents.length - highlight.range.location {
      result.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: highlight.range)
    }
    return result
  }

  var contents: NSMutableAttributedString
  var lineSpacing: CGFloat?

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> ParagraphUIView {
    let openUrlFunction = openURL.callAsFunction(_:)
    let view = ParagraphViewCache.shared.createOrReuseView(contents: contents, lineSpacing: lineSpacing)
    view.onUrlTap = openUrlFunction
    view.setParagraphContents(displayedContents, lineSpacing: lineSpacing, animatedByWord: false)
    view.setTextContextMenu(config.resolvedTextContextMenu)
    view.setMarkdownController(markdownController)
    view.sourceBlockID = sourceBlockID

    if config.shouldAnimateText {
      view.alpha = 0
      UIView.animate(withDuration: ParagraphUIView.animationDuration) {
        view.alpha = 1
      }
    }

    return view
  }

  func updateUIView(_ view: ParagraphUIView, context: Context) {
    if view.paragraphContents != displayedContents || view.lineSpacing != lineSpacing {
      let shouldAnimate = view.window != nil && config.shouldAnimateText // only animate when visible
      view.setParagraphContents(displayedContents, lineSpacing: lineSpacing, animatedByWord: shouldAnimate)
    }
    view.setTextContextMenu(config.resolvedTextContextMenu)
    view.setMarkdownController(markdownController)
    view.sourceBlockID = sourceBlockID
  }

  // If we don't implement this function, the snapshot tests will fail with incorrect sizing.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: ParagraphUIView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0, width.isFinite else {
      return nil
    }

    // Check if content or lineSpacing changed - if so, clear the cache
    if contents != context.coordinator.lastContents || lineSpacing != context.coordinator.lastLineSpacing {
      context.coordinator.sizeCache.removeAll()
      context.coordinator.lastContents = contents
      context.coordinator.lastLineSpacing = lineSpacing
    }

    // Round width to avoid cache misses from floating point precision issues
    let cacheKey = (width * 10).rounded() / 10 // Round to 1 decimal place

    // Check if we have a cached size for this width
    if let cachedSize = context.coordinator.sizeCache[cacheKey] {
      return cachedSize
    }

    // Calculate new size
    let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    let size = uiView.sizeThatFits(targetSize)
    let calculatedSize = CGSize(width: size.width, height: size.height.rounded(.up))

    context.coordinator.sizeCache[cacheKey] = calculatedSize

    return calculatedSize
  }

  class Coordinator {
    // Cache all calculated sizes keyed by width
    var sizeCache: [CGFloat: CGSize] = [:]
    var lastContents: NSMutableAttributedString?
    var lastLineSpacing: CGFloat?
  }
}

extension ParagraphView: Equatable {
  static func == (lhs: ParagraphView, rhs: ParagraphView) -> Bool {
    lhs.contents == rhs.contents && lhs.lineSpacing == rhs.lineSpacing
  }
}
#endif
