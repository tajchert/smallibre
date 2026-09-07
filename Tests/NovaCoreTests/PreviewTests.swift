import XCTest
@testable import NovaCore

final class PreviewTests: XCTestCase {
    func testPreviewStripsActiveContentAndBlocksNetwork() throws {
        let source = Data("<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><base href=\"https://example.org/\"/><script>alert(1)</script></head><body onload=\"fetch('/secret')\"><iframe src=\"https://example.org/\"/><p>Keep this text.</p></body></html>".utf8)
        let html = String(data: try PreviewSanitizer.html(source), encoding: .utf8)!
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertFalse(html.contains("onload="))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("Keep this text."))
    }
}
