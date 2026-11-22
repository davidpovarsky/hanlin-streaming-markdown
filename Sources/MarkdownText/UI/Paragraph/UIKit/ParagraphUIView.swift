//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import iosMath
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AccessibilityContent {
  let label: String?
  let actions: [UIAccessibilityCustomAction]
}

private struct CachedParagraphUIViewSize {
  let size: CGSize
  let targetWidth: CGFloat
}

class ParagraphUIView: UITextView {
  let selectionActivityID = UUID()
  var onSelectionActivity: (@MainActor @Sendable (UUID, Bool) -> Void)?
  var sourceBlockID: String?
  private var isApplyingContents = false
  var onSelectionChanged: (@MainActor (MarkdownTextSelection) -> Void)?
  var onLongPressPreview: (@MainActor (UIView, CGPoint) -> Void)? {
    didSet {
      let enabled = onLongPressPreview != nil
      if previewRecognizer.isEnabled != enabled { previewRecognizer.isEnabled = enabled }
      if (oldValue != nil) != enabled { configureAccessibility(for: attributedText) }
    }
  }
  /// A rich attachment has one atomic position in the enclosing document.
  /// Its inner text keeps links, but never becomes a competing selection owner.
  var usesEnclosingDocumentSelection = false {
    didSet {
      isSelectable = !usesEnclosingDocumentSelection
      embeddedLinkRecognizer.isEnabled = usesEnclosingDocumentSelection
      if oldValue != usesEnclosingDocumentSelection { configureAccessibility(for: attributedText) }
    }
  }
  private lazy var embeddedLinkDelegate = MarkdownEmbeddedLinkGestureDelegate(textView: self)
  private lazy var embeddedLinkRecognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(openEmbeddedLink(_:)))
    recognizer.delegate = embeddedLinkDelegate
    recognizer.isEnabled = false
    addGestureRecognizer(recognizer)
    return recognizer
  }()

  @objc private func openEmbeddedLink(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, let url = embeddedLink(at: recognizer.location(in: self)) else { return }
    onUrlTap(url)
  }

  /// UITextInput geometry is public and respects RTL, text insets and scrolling.
  /// The nearest insertion position alone is insufficient: a blank-area tap
  /// must not activate whichever link happens to be closest.
  fileprivate func embeddedLink(at point: CGPoint) -> URL? {
    guard usesEnclosingDocumentSelection, let nearest = closestPosition(to: point) else { return nil }
    let offset = self.offset(from: beginningOfDocument, to: nearest)
    for index in [offset, offset - 1] where index >= 0 && index < textStorage.length {
      let character = (textStorage.string as NSString).rangeOfComposedCharacterSequence(at: index)
      guard let start = position(from: beginningOfDocument, offset: character.location),
            let end = position(from: start, offset: character.length), let range = textRange(from: start, to: end),
            firstRect(for: range).insetBy(dx: -2, dy: -2).contains(point) else { continue }
      let attributes = textStorage.attributes(at: character.location, effectiveRange: nil)
      if let citation = (attributes[.attachment] as? InlineCitationAttachment)?.citationData { return citation.url }
      if let url = Self.linkURL(attributes[.link]) { return url }
    }
    return nil
  }

  private static func linkURL(_ value: Any?) -> URL? {
    if let url = value as? URL { return url }
    if let string = value as? String { return URL(string: string) }
    return nil
  }

  private lazy var previewDelegate = MarkdownPreviewGestureDelegate(textView: self)
  private lazy var previewRecognizer: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(showMessagePreview(_:)))
    recognizer.minimumPressDuration = 1.0
    recognizer.allowableMovement = 10
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = previewDelegate
    recognizer.isEnabled = false
    addGestureRecognizer(recognizer)
    return recognizer
  }()

  @objc private func showMessagePreview(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, window != nil, let action = onLongPressPreview else { return }
    let location = recognizer.location(in: self)
    resignFirstResponder()
    action(self, location)
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { onSelectionActivity?(selectionActivityID, selectedRange.length > 0) }
    return accepted
  }

  private static let jsonEncoder = JSONEncoder()
  static let animationDuration: CFTimeInterval = ParagraphAnimationConstants.fadeInDuration

  private(set) var paragraphContents: NSMutableAttributedString = NSMutableAttributedString()
  private var appliedContents: NSAttributedString = NSAttributedString(string: "")
  private(set) var lineSpacing: CGFloat?
  private var activeAnimations: [FadeAnimationData] = []
  private var fadeAnimationDisplayLink: CADisplayLink?
  private var cachedSize: CachedParagraphUIViewSize?

  private(set) var attachmentEnvironment: EnvironmentValues?
  private let attachmentProviders = NSHashTable<MarkdownRichBlockViewProvider>.weakObjects()

  func setAttachmentEnvironment(_ environment: EnvironmentValues?) {
    attachmentEnvironment = environment
    for provider in attachmentProviders.allObjects { provider.refreshEnvironment() }
  }

  func registerAttachmentProvider(_ provider: MarkdownRichBlockViewProvider) {
    attachmentProviders.add(provider)
  }

  func attachmentSizeDidChange() {
    invalidateCachedSize()
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  /// Materialize owners only for the changed tail. Canonical attributes remain
  /// untouched, so equality/tail planning never compares live hosting objects.
  private func ownedAttachments(in content: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: content)
    content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
      guard let attachment = value as? MarkdownRichBlockAttachment else { return }
      result.addAttribute(.attachment, value: attachment.owned(by: self), range: range)
    }
    return result
  }

  override func copy(_ sender: Any?) {
    // Copy the exact textual payload of selected rich blocks, not U+FFFC.
    let range = NSIntersectionRange(selectedRange, NSRange(location: 0, length: textStorage.length))
    guard range.length > 0 else { return }
    var containsRichBlock = false
    textStorage.enumerateAttribute(.attachment, in: range) { value, _, stop in
      if value is MarkdownRichBlockAttachment { containsRichBlock = true; stop.pointee = true }
    }
    if containsRichBlock {
      UIPasteboard.general.string = MarkdownTextSelection(attributedText: textStorage,
        selectedRange: range, sourceBlockID: sourceBlockID).text
    } else { super.copy(sender) }
  }

  var textContextMenu: TextContextMenu?
  var markdownController: MarkdownController?

  // To override the behaviour of this property, do so on ParagraphView's SwiftUI wrapper.
  var onUrlTap: (URL) -> Void = { UIApplication.shared.open($0) }

  override init(frame: CGRect, textContainer: NSTextContainer?) {
    super.init(frame: frame, textContainer: textContainer)
    delegate = self
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    delegate = self
    setupView()
  }

  deinit {
    tearDownDisplayLink()
    activeAnimations.removeAll()
  }

  override func willMove(toWindow newWindow: UIWindow?) {
    super.willMove(toWindow: newWindow)
    // Fix for crash: "UIPreviewTarget requires that the container view is in a window". When the view is removed from the window (e.g. scrolled out in LazyVStack), we should clear the selection to prevent any pending menu or drag interactions from trying to reference the detached view.
    if newWindow == nil {
      selectedTextRange = nil
    }
  }

  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result {
      selectedTextRange = nil
      reportSelectionActivity(deferred: true)
    }
    return result
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
      AppAppearance.update(style: traitCollection.userInterfaceStyle)
    }
  }

  override var intrinsicContentSize: CGSize {
    if isScrollEnabled { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    if let cachedSize {
      return cachedSize.size
    }
    var targetWidth = bounds.width
    if targetWidth <= 0 || targetWidth.isInfinite {
      // When bounds.width is not valid, we have to give a best guess, otherwise Chat becomes blank in some cases sometimes. It may be related to LazyVStack.
      targetWidth = UIScreen.main.bounds.width
    }
    let targetSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
    let contentSize = sizeThatFits(targetSize)
    let roundedUpSize = CGSize(width: contentSize.width.rounded(.up), height: contentSize.height.rounded(.up))
    cachedSize = CachedParagraphUIViewSize(size: roundedUpSize, targetWidth: targetWidth)
    return roundedUpSize
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.width != cachedSize?.targetWidth {
      invalidateCachedSize()
    }
    invalidateIntrinsicContentSize()
  }

  func setParagraphContents(_ newContents: NSMutableAttributedString, lineSpacing: CGFloat? = nil, animatedByWord: Bool) {
    // Keep the cached interface style up to date for citation preview rendering.
    // This runs on the main thread so it's safe to read traitCollection here.
    AppAppearance.update(style: traitCollection.userInterfaceStyle)

    guard paragraphContents != newContents || self.lineSpacing != lineSpacing else {
      return
    }
    self.paragraphContents = newContents
    self.lineSpacing = lineSpacing

    let oldAttributedString = appliedContents
    let oldContentLength = oldAttributedString.length
    let previousSelection = selectedRange
    let wasSelecting = isFirstResponder && previousSelection.length > 0
    let finalString: NSMutableAttributedString
    if lineSpacing != nil {
      finalString = applyLineSpacing(to: newContents, lineSpacing: lineSpacing)
    } else {
      finalString = newContents
    }

    guard finalString != oldAttributedString else {
      return
    }

    // Stop display link update before updating the attributed string
    tearDownDisplayLink()
    finishPendingAnimations(using: oldAttributedString)
    invalidateCachedSize()
    let edit = NativeTextEditPlan(old: oldAttributedString, new: finalString)
    isApplyingContents = true
    textStorage.beginEditing()
    textStorage.replaceCharacters(in: edit.replacedRange,
      with: ownedAttachments(in: finalString.attributedSubstring(from: edit.replacementRange)))
    textStorage.endEditing()
    appliedContents = finalString
    // Appending a stream must not dismiss or move an existing native selection.
    // If a speculative rewrite changes that prefix, UIKit establishes a new selection.
    if wasSelecting, edit.preserves(previousSelection) {
      selectedRange = previousSelection
    }

    isApplyingContents = false
    reportSelectionActivity(deferred: true)
    configureAccessibility(for: finalString)

    invalidateIntrinsicContentSize()

    let newContentLength = finalString.length - oldContentLength

    if animatedByWord,
       newContentLength > 0 {
      // Animate word by word
      let newContentRange = NSRange(location: oldContentLength, length: newContentLength)
      let wordRanges = attributedText.splitIntoWords(withIn: newContentRange)
      let wordCount = wordRanges.count
      let delayBetweenWords: Double = ParagraphAnimationConstants.delayBetweenWordsRatio / Double(wordCount)
      let baseStartTime = CACurrentMediaTime()
      for (index, wordRange) in wordRanges.enumerated() {
        let animationData = FadeAnimationData(
          startTime: baseStartTime + Double(index) * delayBetweenWords,
          duration: Self.animationDuration,
          range: wordRange
        )
        activeAnimations.append(animationData)
      }

      updateTextViewWithCurrentAnimations()

      if fadeAnimationDisplayLink == nil {
        setUpDisplayLink()
      }
    } else {
      // If no animation needed anymore, clean up all existings animations if any.
      activeAnimations.removeAll()
    }
  }

  private func applyLineSpacing(to attributedString: NSMutableAttributedString, lineSpacing: CGFloat?) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: attributedString)
    if let lineSpacing {
      result.setLineSpacing(lineSpacing)
    }
    return result
  }

  private func finishPendingAnimations(using canonical: NSAttributedString) {
    guard !activeAnimations.isEmpty else { return }
    textStorage.beginEditing()
    for animation in activeAnimations where NSMaxRange(animation.range) <= canonical.length {
      canonical.enumerateAttribute(.foregroundColor, in: animation.range) { value, range, _ in
        if let value { self.textStorage.addAttribute(.foregroundColor, value: value, range: range) }
        else { self.textStorage.removeAttribute(.foregroundColor, range: range) }
      }
    }
    textStorage.endEditing()
    activeAnimations.removeAll()
  }

  private func setupView() {
    // Only register if not already registered to prevent conflicts
    if NSTextAttachment.textAttachmentViewProviderClass(forFileType: UTType.data.identifier) == nil {
      NSTextAttachment.registerViewProviderClass(LatexViewProvider.self, forFileType: UTType.data.identifier)
    }

    if NSTextAttachment.textAttachmentViewProviderClass(forFileType: MarkdownRichBlockAttachment.contentType) == nil {
      NSTextAttachment.registerViewProviderClass(MarkdownRichBlockViewProvider.self,
        forFileType: MarkdownRichBlockAttachment.contentType)
    }

    isEditable = false
    isSelectable = true
    isScrollEnabled = false
    textAlignment = .natural
    adjustsFontForContentSizeCategory = true
    backgroundColor = .clear
    if #available(iOS 18.0, *) {
      writingToolsBehavior = .none
    }

    setContentHuggingPriority(.defaultHigh, for: .vertical)
    setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    textContainerInset = .zero
    textContainer.lineFragmentPadding = 0
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    textContainer.maximumNumberOfLines = 0
    textContainer.lineBreakMode = .byWordWrapping

    // When this is empty, UITextView will not override the styles set by attributes
    self.linkTextAttributes = [:]

    // Disable drag interaction to prevent crashes related to dragging from a view that might disappear
    textDragInteraction?.isEnabled = false
  }

  /// Creates a custom accessibility action that forwards activation to `onUrlTap`.
  private func makeAccessibilityAction(name: String, url: URL) -> UIAccessibilityCustomAction {
    return UIAccessibilityCustomAction(name: name) { [weak self] _ in
      guard let self else { return false }
      self.onUrlTap(url)
      return true
    }
  }

  /// Generate accessibility label and actions in a single pass (optimized)
  private func generateAccessibilityContent(from attributedString: NSAttributedString) -> AccessibilityContent? {
    var labelComponents: [String] = []
    var actions: [UIAccessibilityCustomAction] = []
    var hasRichContent = false
    let fullRange = NSRange(location: 0, length: attributedString.length)

    attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
      // Handle citation attachments
      if let attachment = attrs[.attachment] as? InlineCitationAttachment,
         let citationData = attachment.citationData {
        // Add to accessibility label
        labelComponents.append(citationData.accessibilityLabel)

        // Create accessibility action for citations
        let actionName = String.openCitation(citationLabel: citationData.accessibilityLabel)
        let action = makeAccessibilityAction(name: actionName, url: citationData.url)
        actions.append(action)
      } else if let attachment = attrs[.attachment] as? MarkdownRichBlockAttachment {
        hasRichContent = true
        labelComponents.append(attachment.selectionText)
      } else {
        // Add the regular text for this range
        let substring = attributedString.attributedSubstring(from: range)
        let text = substring.string
        if !text.isEmpty {
          labelComponents.append(text)
          if usesEnclosingDocumentSelection, let url = Self.linkURL(attrs[.link]) {
            actions.append(makeAccessibilityAction(name: text, url: url))
          }
        }
      }
    }

    let accessibilityLabel = labelComponents.isEmpty ? nil : labelComponents.joined()

    // Return nil if no attachments were found
    guard !actions.isEmpty || hasRichContent else { return nil }

    return AccessibilityContent(label: accessibilityLabel, actions: actions)
  }

  /// Configure accessibility properties for the text view
  private func configureAccessibility(for attributedString: NSAttributedString) {
    // Generate the full accessibility content directly
    if let accessibilityContent = generateAccessibilityContent(from: attributedString) {
      // We have citations, use the generated content
      accessibilityAttributedLabel = nil
      accessibilityLabel = accessibilityContent.label
      accessibilityCustomActions = accessibilityContent.actions
    } else {
      // No citations found, just use the plain text
      accessibilityAttributedLabel = attributedString
      accessibilityCustomActions = nil
    }
    if onLongPressPreview != nil {
      let action = UIAccessibilityCustomAction(name: NSLocalizedString("Message actions", comment: "Long-hold message preview and actions")) { [weak self] _ in
        guard let self, self.window != nil, let preview = self.onLongPressPreview else { return false }
        preview(self, CGPoint(x: self.bounds.midX, y: self.bounds.midY))
        return true
      }
      accessibilityCustomActions = (accessibilityCustomActions ?? []) + [action]
    }
  }

  @objc private func updateFadeAnimation() {
    let currentTime = CACurrentMediaTime()
    var completedAnimations: [UUID] = []

    updateTextViewWithCurrentAnimations()

    // Remove completed animations
    for animation in activeAnimations {
      let elapsed = currentTime - animation.startTime
      let progress = elapsed / animation.duration

      if progress >= 1.0 {
        completedAnimations.append(animation.id)
      }
    }
    activeAnimations.removeAll { completedAnimations.contains($0.id) }

    if activeAnimations.isEmpty {
      tearDownDisplayLink()
    }
  }

  private func updateTextViewWithCurrentAnimations() {
    let currentTime = CACurrentMediaTime()

    textStorage.beginEditing()
    defer { textStorage.endEditing() }

    for animation in activeAnimations {
      guard animation.range.location + animation.range.length <= textStorage.length else {
        continue
      }
      let elapsed = currentTime - animation.startTime
      let animatedAlpha: CGFloat

      if elapsed < 0 {
        animatedAlpha = 0.0
      } else {
        let progress = min(max(elapsed / animation.duration, 0.0), 1.0)
        let easedProgress = paragraphEaseOut(progress)
        animatedAlpha = easedProgress
      }

      // Apply alpha to this animation's range, preserving each span's
      // existing foreground color. Spans with no foreground color get a
      // sensible default so they still fade in instead of disappearing.
      let defaultColor = UIColor(Color.Theme.Foreground.Primary.Primary750)
      textStorage.enumerateAttribute(.foregroundColor, in: animation.range, options: []) { value, range, _ in
        let baseColor = (value as? UIColor) ?? defaultColor
        textStorage.addAttribute(.foregroundColor, value: baseColor.withAlphaComponent(animatedAlpha), range: range)
      }
    }
  }

  private func setUpDisplayLink() {
    fadeAnimationDisplayLink = CADisplayLink(target: self, selector: #selector(updateFadeAnimation))
    fadeAnimationDisplayLink?.preferredFramesPerSecond = 60
    fadeAnimationDisplayLink?.add(to: .main, forMode: .common)
  }

  private func tearDownDisplayLink() {
    fadeAnimationDisplayLink?.remove(from: .main, forMode: .common)
    fadeAnimationDisplayLink = nil
  }

  private func invalidateCachedSize() {
    cachedSize = nil
  }

  func setTextContextMenu(_ menu: TextContextMenu?) {
    textContextMenu = menu
  }

  func setMarkdownController(_ controller: MarkdownController?) {
    markdownController = controller
  }
}

// MARK: - UITextViewDelegate
extension ParagraphUIView: UITextViewDelegate {
  fileprivate func reportSelectionActivity(deferred: Bool = false) {
    guard !isApplyingContents else { return }
    if deferred {
      // UIViewRepresentable content/removal updates must not synchronously
      // mutate the enclosing SwiftUI chat's state. Read the latest selection.
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.onSelectionActivity?(self.selectionActivityID, self.isFirstResponder && self.selectedRange.length > 0)
        self.publishSelection()
      }
    } else {
      onSelectionActivity?(selectionActivityID, isFirstResponder && selectedRange.length > 0)
      publishSelection()
    }
  }

  private func publishSelection() {
    onSelectionChanged?(MarkdownTextSelection(attributedText: attributedText,
      selectedRange: isFirstResponder ? selectedRange : NSRange(location: 0, length: 0), sourceBlockID: sourceBlockID))
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    reportSelectionActivity(deferred: !(textView.isFirstResponder && textView.selectedRange.length > 0))
  }

  func textViewDidBeginEditing(_ textView: UITextView) { textViewDidChangeSelection(textView) }

  func textViewDidEndEditing(_ textView: UITextView) { reportSelectionActivity(deferred: true) }

  func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
    self.onUrlTap(URL)
    return false
  }

  func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange) -> Bool {
    // Check if this is our custom citation attachment with pre-decoded data
    if let citationAttachment = textAttachment as? InlineCitationAttachment,
       let citationData = citationAttachment.citationData {
      self.onUrlTap(citationData.url)
      return false
    }

    return false
  }

  func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
    guard let textContextMenu else { return nil }
    return textContextMenu.buildUIMenu(
      textView: textView,
      selectedRange: range,
      suggestedActions: suggestedActions,
      markdownController: markdownController
    )
  }

  func textView(_ textView: UITextView, willPresentEditMenuWith animator: any UIEditMenuInteractionAnimating) {
    guard let textContextMenu, let markdownController else { return }
    let clampedRange = NSIntersectionRange(textView.selectedRange, NSRange(location: 0, length: textView.attributedText.length))
    let selectedText = textView.attributedText.attributedSubstring(from: clampedRange).string
    for group in textContextMenu.menuGroups {
      for item in group.items where item.id != TextSelectionConfig.selectMoreItemID {
        markdownController.onContextMenuAppear(id: item.id, selectedContent: selectedText)
      }
    }
  }
}

/// Only a precise link/citation tap is consumed by an inner rich text leaf.
/// All other touches remain available to the enclosing document and controls.
private final class MarkdownEmbeddedLinkGestureDelegate: NSObject, UIGestureRecognizerDelegate {
  weak var textView: ParagraphUIView?
  init(textView: ParagraphUIView) { self.textView = textView }
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let textView else { return false }
    return textView.embeddedLink(at: gestureRecognizer.location(in: textView)) != nil
  }
}

/// Public gesture arbitration only. A selection already in progress (including
/// a handle drag) can never become a message preview. A new stationary hold can
/// coexist with UIKit's initial word selection; moving >10pt cancels the preview.
private final class MarkdownPreviewGestureDelegate: NSObject, UIGestureRecognizerDelegate {
  weak var textView: ParagraphUIView?
  init(textView: ParagraphUIView) { self.textView = textView }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard let view = textView, view.onLongPressPreview != nil,
          !(view.isFirstResponder && view.selectedRange.length > 0) else { return false }
    var touched = touch.view
    while let current = touched, current !== view {
      if current is MarkdownRichBlockHostView || current is UIControl { return false }
      touched = current.superview
    }
    let point = touch.location(in: view)
    if let position = view.closestPosition(to: point) {
      let index = view.offset(from: view.beginningOfDocument, to: position)
      if index >= 0, index < view.attributedText.length,
         view.attributedText.attribute(.link, at: index, effectiveRange: nil) != nil { return false }
    }
    return true
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    true
  }
}

fileprivate extension NSMutableAttributedString {
  func setLineSpacing(_ lineSpacing: CGFloat) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.alignment = .natural
    addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: length))
  }
}
#endif
