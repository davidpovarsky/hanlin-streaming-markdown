// Copyright (c) 2026 Hanlin contributors. Licensed under the MIT License.

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Canonical parser attachments are immutable. A native text view creates its
/// own weakly owned copy only when that attachment enters the changed tail.
final class MarkdownRichBlockAttachment: NSTextAttachment {
  static let contentType = "com.hanlin.markdown.rich-block"
  let block: MarkdownRenderable
  let selectionText: String
  @MainActor weak var owner: ParagraphUIView?

  init(block: MarkdownRenderable, selectionText: String) {
    self.block = block
    self.selectionText = selectionText
    super.init(data: nil, ofType: Self.contentType)
    allowsTextAttachmentView = true
  }

  required init?(coder: NSCoder) { return nil }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? MarkdownRichBlockAttachment else { return false }
    return block == other.block && selectionText == other.selectionText
  }

  override var hash: Int { block.id.hashValue ^ selectionText.hashValue }

  @MainActor func owned(by owner: ParagraphUIView) -> MarkdownRichBlockAttachment {
    let copy = MarkdownRichBlockAttachment(block: block, selectionText: selectionText)
    copy.owner = owner
    return copy
  }
}

/// Public TextKit 2 view attachment. SwiftUI retains the original rich block
/// type/state; no raster snapshot or sibling selection surface is substituted.
final class MarkdownRichBlockViewProvider: NSTextAttachmentViewProvider {
  private weak var owner: ParagraphUIView?
  private let block: MarkdownRenderable
  private var host: MarkdownRichBlockHostView?
  private var lastSize = CGSize.zero

  required override init(textAttachment attachment: NSTextAttachment, parentView: UIView?,
                         textLayoutManager: NSTextLayoutManager?, location: any NSTextLocation) {
    let rich = attachment as? MarkdownRichBlockAttachment
    self.block = rich?.block ?? .thematicBreak(id: "unavailable")
    self.owner = rich?.owner
    super.init(textAttachment: attachment, parentView: parentView,
      textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
    owner?.registerAttachmentProvider(self)
  }

  override func loadView() {
    let host = MarkdownRichBlockHostView()
    self.host = host
    self.view = host
    refreshEnvironment()
  }

  func refreshEnvironment() {
    guard let host else { return }
    guard let environment = owner?.attachmentEnvironment else { host.clear(); return }
    // Updating the configuration of the same content view preserves the hosted
    // view's identity while refreshing actions, locale, RTL, theme and Dynamic Type.
    host.update(block: block, environment: environment) { [weak self] size in
      self?.contentSizeChanged(size)
    }
  }

  override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                 location: any NSTextLocation, textContainer: NSTextContainer?,
                                 proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
    if host == nil { loadView() }
    let proposedWidth = proposedLineFragment.width
    let fallbackWidth = owner?.bounds.width ?? 1
    let width = max(1, proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : fallbackWidth)
    let size = host?.fittingSize(width: width) ?? CGSize(width: width, height: 1)
    lastSize = size
    // A block attachment fills its own paragraph's available line width.
    // Keep its bottom on the baseline; TextKit supplies the paragraph spacing.
    return CGRect(x: 0, y: 0, width: width, height: max(1, size.height.rounded(.up)))
  }

  private func contentSizeChanged(_ size: CGSize) {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
          abs(size.height - lastSize.height) > 0.5 || abs(size.width - lastSize.width) > 0.5 else { return }
    lastSize = size
    // Geometry changes arrive after SwiftUI layout. Defer invalidation to avoid
    // changing text layout recursively during an attachment's own measurement.
    Task { @MainActor [weak self] in
      guard let self, self.owner?.window != nil else { return }
      self.textLayoutManager?.invalidateLayout(for: NSTextRange(location: self.location))
      self.owner?.attachmentSizeDidChange()
    }
  }
}

/// Its public type also gives gesture arbitration an explicit boundary for
/// embedded buttons/links, without inspecting UIKit's private view hierarchy.
final class MarkdownRichBlockHostView: UIView {
  private var content: (any UIView & UIContentView)?

  func update(block: MarkdownRenderable, environment: EnvironmentValues,
              sizeChanged: @escaping @MainActor (CGSize) -> Void) {
    let configuration = UIHostingConfiguration {
      MarkdownRichBlockContent(block: block, environment: environment, sizeChanged: sizeChanged)
    }.margins(.all, 0).minSize(width: 0, height: 0)
    if let content {
      content.configuration = configuration
    } else {
      let content = configuration.makeContentView()
      self.content = content
      addSubview(content)
      content.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: leadingAnchor),
        content.trailingAnchor.constraint(equalTo: trailingAnchor),
        content.topAnchor.constraint(equalTo: topAnchor),
        content.bottomAnchor.constraint(equalTo: bottomAnchor)
      ])
    }
    invalidateIntrinsicContentSize()
  }

  func clear() {
    content?.removeFromSuperview()
    content = nil
  }

  func fittingSize(width: CGFloat) -> CGSize {
    guard let content else { return CGSize(width: width, height: 1) }
    let size = content.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    return CGSize(width: width, height: max(1, size.height))
  }
}

private struct MarkdownRichBlockContent: View {
  let block: MarkdownRenderable
  let environment: EnvironmentValues
  let sizeChanged: @MainActor (CGSize) -> Void

  var body: some View {
    SingleBlockView(renderable: block)
      .environment(\.self, environment)
      .environment(\.markdownIsRichAttachment, true)
      .environment(\.markdownLongPressPreview, nil)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { sizeChanged($0) }
  }
}
#endif
