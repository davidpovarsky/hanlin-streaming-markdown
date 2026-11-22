//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import SwiftUI

struct ParagraphView: UIViewRepresentable {
  @Environment(\.markdownSelectionActivity) var selectionActivity
  @Environment(\.openURL) var openURL
  @Environment(\.markdownConfig) var config: MarkdownRenderConfig
  @Environment(\.markdownController) var markdownController: MarkdownController?

  @Environment(\.markdownSelectionBlockID) var sourceBlockID
  @Environment(\.markdownSelectionHighlight) var highlight
  @Environment(\.markdownSelectionDocument) var selectionDocument
  @Environment(\.markdownSelectionChanged) var selectionChanged
  @Environment(\.markdownSelectAllRequest) var selectAllRequest
  @Environment(\.markdownLongPressPreview) var longPressPreview

  private var displayedContents: NSMutableAttributedString {
    guard highlight != nil else { return contents }
    let result = NSMutableAttributedString(attributedString: contents)
    MarkdownSelectionHighlight.apply(highlight, to: result, sourceBlockID: sourceBlockID, document: selectionDocument)
    return result
  }

  var contents: NSMutableAttributedString
  var lineSpacing: CGFloat?
  var scrolls = false

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
    view.onSelectionActivity = selectionActivity
    configureSelection(view, coordinator: context.coordinator)

    if config.shouldAnimateText {
      view.alpha = 0
      UIView.animate(withDuration: ParagraphUIView.animationDuration) {
        view.alpha = 1
      }
    }

    return view
  }

  func updateUIView(_ view: ParagraphUIView, context: Context) {
    // A retained paragraph must use its current SwiftUI presenter's action,
    // including after the host changes while the native text view stays mounted.
    view.onUrlTap = openURL.callAsFunction(_:)
    let displayed = displayedContents
    let shouldAnimate = view.window != nil && config.shouldAnimateText // only animate when visible
    view.setParagraphContents(displayed, lineSpacing: lineSpacing, animatedByWord: shouldAnimate)
    view.setTextContextMenu(config.resolvedTextContextMenu)
    view.setMarkdownController(markdownController)
    view.sourceBlockID = sourceBlockID
    view.onSelectionActivity = selectionActivity
    configureSelection(view, coordinator: context.coordinator)
  }

  static func dismantleUIView(_ view: ParagraphUIView, coordinator: Coordinator) {
    let handler = view.onSelectionActivity
    let id = view.selectionActivityID
    Task { @MainActor in handler?(id, false) }
    view.onSelectionActivity = nil
    view.onSelectionChanged = nil
    view.onLongPressPreview = nil
    view.setMarkdownController(nil)
    view.setTextContextMenu(nil)
    view.onUrlTap = { _ in }
  }

  // If we don't implement this function, the snapshot tests will fail with incorrect sizing.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: ParagraphUIView, context: Context) -> CGSize? {
    guard !scrolls else { return nil }
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
    var isApplyingSelectAll = false
  }

  private func configureSelection(_ view: ParagraphUIView, coordinator: Coordinator) {
    view.isScrollEnabled = scrolls
    view.textContainerInset = scrolls ? UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20) : .zero
    view.onSelectionChanged = selectionChanged
    view.onLongPressPreview = scrolls ? nil : longPressPreview
    guard let request = selectAllRequest, request.wrappedValue, scrolls, !coordinator.isApplyingSelectAll else { return }
    coordinator.isApplyingSelectAll = true
    Task { @MainActor [weak view] in
      defer { coordinator.isApplyingSelectAll = false; request.wrappedValue = false }
      guard let view, view.window != nil else { return }
      view.becomeFirstResponder()
      view.selectAll(nil)
    }
  }
}

extension ParagraphView: Equatable {
  static func == (lhs: ParagraphView, rhs: ParagraphView) -> Bool {
    lhs.contents == rhs.contents && lhs.lineSpacing == rhs.lineSpacing && lhs.scrolls == rhs.scrolls
  }
}
#endif
