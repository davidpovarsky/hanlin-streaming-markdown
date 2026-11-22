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
  private let block: MarkdownRenderable
  private let layoutCache = MarkdownRichBlockLayoutCache()
  @MainActor private weak var owner: ParagraphUIView?
  @MainActor private var host: MarkdownRichBlockHostView?
  @MainActor private var invalidationScheduled = false

  required override init(textAttachment attachment: NSTextAttachment, parentView: UIView?,
                         textLayoutManager: NSTextLayoutManager?, location: any NSTextLocation) {
    let rich = attachment as? MarkdownRichBlockAttachment
    self.block = rich?.block ?? .thematicBreak(id: "unavailable")
    super.init(textAttachment: attachment, parentView: parentView,
      textLayoutManager: textLayoutManager, location: location)
    if Thread.isMainThread {
      MainActor.assumeIsolated { connectOwner() }
    } else if layoutCache.requestSetup() {
      enqueueMainUpdate()
    }
  }

  override func loadView() {
    if Thread.isMainThread {
      MainActor.assumeIsolated { ensureHost() }
    } else if layoutCache.requestSetup() {
      enqueueMainUpdate()
    }
  }

  @MainActor private func connectOwner() {
    tracksTextAttachmentViewBounds = true
    guard owner == nil, let currentOwner = (textAttachment as? MarkdownRichBlockAttachment)?.owner else { return }
    owner = currentOwner
    currentOwner.registerAttachmentProvider(self)
  }

  @MainActor private func ensureHost() {
    connectOwner()
    guard host == nil else { return }
    let host = MarkdownRichBlockHostView()
    self.host = host
    self.view = host
    refreshEnvironment()
  }

  @MainActor func refreshEnvironment() {
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
    let width = proposedLineFragment.width
    if Thread.isMainThread {
      return MainActor.assumeIsolated { measureOnMain(proposedWidth: width).bounds }
    }
    // TextKit's public provider callbacks have no main-thread contract. Never
    // read a UIView here or block a layout worker waiting for the main queue.
    let snapshot = layoutCache.bounds(proposedWidth: width)
    if snapshot.needsHandoff { enqueueMainUpdate() }
    return snapshot.bounds
  }

  @MainActor private func measureOnMain(proposedWidth: CGFloat) -> (bounds: CGRect, changed: Bool) {
    // loadView is a framework entry point, not a helper to invoke ourselves.
    ensureHost()
    let fallbackWidth = owner?.bounds.width ?? 1
    let width = max(1, proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : fallbackWidth)
    let measured = host?.fittingSize(width: width) ?? CGSize(width: width, height: 1)
    let height = measured.height.isFinite ? max(1, measured.height.rounded(.up)) : 1
    let size = CGSize(width: width, height: height)
    let changed = layoutCache.store(size)
    // A block attachment fills its own paragraph's available line width.
    // Keep its bottom on the baseline; TextKit supplies the paragraph spacing.
    return (CGRect(origin: .zero, size: size), changed)
  }

  private func enqueueMainUpdate() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let width = self.layoutCache.beginHandoff()
      let measurement = self.measureOnMain(proposedWidth: width ?? 0)
      if measurement.changed { self.scheduleLayoutInvalidation() }
    }
  }

  @MainActor private func contentSizeChanged(_ size: CGSize) {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
    let measured = CGSize(width: size.width, height: max(1, size.height.rounded(.up)))
    if layoutCache.store(measured) { scheduleLayoutInvalidation() }
  }

  @MainActor private func scheduleLayoutInvalidation() {
    guard !invalidationScheduled else { return }
    invalidationScheduled = true
    // Geometry changes arrive after SwiftUI layout. Defer invalidation to avoid
    // changing text layout recursively during an attachment's own measurement.
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.invalidationScheduled = false
      // A live text view can be measured before it enters a window. Teardown
      // clears the environment; window presence must not discard fresh geometry.
      guard let owner = self.owner, owner.attachmentEnvironment != nil else { return }
      self.textLayoutManager?.invalidateLayout(for: NSTextRange(location: self.location))
      owner.attachmentSizeDidChange()
    }
  }
}

/// The only state shared with a non-main TextKit measurement callback. No UI,
/// framework layout object, closure, or actor reference is accessed under this lock.
private final class MarkdownRichBlockLayoutCache {
  private let lock = NSLock()
  private var size = CGSize.zero
  private var requestedWidth: CGFloat?
  private var handoffPending = false

  func requestSetup() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !handoffPending else { return false }
    handoffPending = true
    return true
  }

  func bounds(proposedWidth: CGFloat) -> (bounds: CGRect, needsHandoff: Bool) {
    lock.lock()
    defer { lock.unlock() }
    let width = max(1, proposedWidth.isFinite && proposedWidth > 0 ? proposedWidth : max(1, size.width))
    let needsMeasurement = size.height <= 0 || abs(size.width - width) > 0.5
    var needsHandoff = false
    if needsMeasurement {
      requestedWidth = width
      if !handoffPending {
        handoffPending = true
        needsHandoff = true
      }
    }
    return (CGRect(x: 0, y: 0, width: width, height: max(1, size.height)), needsHandoff)
  }

  func beginHandoff() -> CGFloat? {
    lock.lock()
    defer { lock.unlock() }
    let width = requestedWidth
    requestedWidth = nil
    handoffPending = false
    return width
  }

  @discardableResult func store(_ newSize: CGSize) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let changed = abs(size.height - newSize.height) > 0.5 || abs(size.width - newSize.width) > 0.5
    size = newSize
    return changed
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
