#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import SwiftStreamingMarkdown

final class ParagraphLinkHostTests: XCTestCase {
  @MainActor
  func testMountedParagraphUsesUpdatedHostLinkAction() async throws {
    let state = LinkHostState()
    let host = UIHostingController(rootView: LinkHostView(state: state))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true; window.rootViewController = nil }
    host.view.layoutIfNeeded()
    for _ in 0..<50 where paragraph(in: host.view) == nil {
      try await Task.sleep(for: .milliseconds(10))
      host.view.layoutIfNeeded()
    }
    let original = try XCTUnwrap(paragraph(in: host.view))
    let url = try XCTUnwrap(URL(string: "https://example.com/retained-paragraph"))
    original.onUrlTap(url)
    XCTAssertEqual(state.receivedRevisions, [0])

    state.revision = 1
    // Await the actual representable content update, not an assumed delay.
    for _ in 0..<50 where original.paragraphContents.string != "Host revision 1" {
      try await Task.sleep(for: .milliseconds(10))
      host.view.layoutIfNeeded()
    }
    XCTAssertEqual(original.paragraphContents.string, "Host revision 1")
    XCTAssertTrue(paragraph(in: host.view) === original,
                  "This regression must update the mounted view instead of testing a replacement")
    original.onUrlTap(url)
    XCTAssertEqual(state.receivedRevisions, [0, 1],
                   "A retained native paragraph must not call the old host's URL action")
    XCTAssertEqual(state.receivedURLs, [url, url])
  }

  @MainActor
  private func paragraph(in view: UIView) -> ParagraphUIView? {
    if let paragraph = view as? ParagraphUIView { return paragraph }
    for child in view.subviews {
      if let match = paragraph(in: child) { return match }
    }
    return nil
  }
}

@MainActor
private final class LinkHostState: ObservableObject {
  @Published var revision = 0
  var receivedRevisions: [Int] = []
  var receivedURLs: [URL] = []
}

@MainActor
private struct LinkHostView: View {
  @ObservedObject var state: LinkHostState

  var body: some View {
    let revision = state.revision
    ParagraphView(contents: NSMutableAttributedString(string: "Host revision \(revision)"),
                  lineSpacing: nil)
      .environment(\.openURL, OpenURLAction { url in
        state.receivedRevisions.append(revision)
        state.receivedURLs.append(url)
        return .handled
      })
  }
}
#endif
