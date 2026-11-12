//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class CodeBlockRendererTests: XCTestCase {
  func testDefaultRendererRemainsOptIn() {
    XCTAssertNil(EnvironmentValues().markdownCodeBlockRenderer)
  }

  func testParsedBlocksKeepLiteralSourceAndStableSelectionIdentity() async {
    let parser = MarkdownParserImpl()
    let first = await parser.parse(text: "Intro\n\n```mermaid\nsequenceDiagram\nA->>B: שלום\n", config: .default)
    let second = await parser.parse(text: "Intro\n\n```mermaid\nsequenceDiagram\nA->>B: שלום\n```\n\nAfter", config: .default)
    let partial = codeBlocks(in: first)
    let complete = codeBlocks(in: second)
    XCTAssertEqual(partial.count, 1)
    XCTAssertEqual(complete.count, 1)
    XCTAssertEqual(partial.first?.id, complete.first?.id)
    XCTAssertEqual(complete.first?.language, "mermaid")
    XCTAssertEqual(complete.first?.code, "sequenceDiagram\nA->>B: שלום\n")
  }

  #if canImport(UIKit)
  @MainActor
  func testViewHookReceivesTheExistingParsedBlock() async {
    let rendered = expectation(description: "AST code-block renderer invoked")
    let capture = Capture(expectation: rendered)
    let view = MarkdownView(text: "Intro\n\n```mermaid\nflowchart LR\nA-->B\n```", config: .default)
      .markdownCodeBlockRenderer { block in
        capture.accept(block)
        return AnyView(Text("Rendered diagram fixture"))
      }
    let host = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.layoutIfNeeded()
    await fulfillment(of: [rendered], timeout: 5)
    XCTAssertEqual(capture.block?.id, "1")
    XCTAssertEqual(capture.block?.language, "mermaid")
    XCTAssertEqual(capture.block?.code, "flowchart LR\nA-->B\n")
  }

  @MainActor
  private final class Capture {
    let expectation: XCTestExpectation
    private(set) var block: MarkdownCodeBlock?

    init(expectation: XCTestExpectation) { self.expectation = expectation }

    func accept(_ block: MarkdownCodeBlock) {
      guard self.block == nil else { return }
      self.block = block
      expectation.fulfill()
    }
  }
  #endif

  private func codeBlocks(in document: RenderableDocument) -> [MarkdownCodeBlock] {
    document.renderables.compactMap { block in
      guard case .codeBlock(let id, let language, let code) = block else { return nil }
      return MarkdownCodeBlock(id: id, language: language, code: code)
    }
  }
}
