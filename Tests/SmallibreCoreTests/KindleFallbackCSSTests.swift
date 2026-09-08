import XCTest
@testable import SmallibreCore

final class KindleFallbackCSSTests: XCTestCase {
    func testDropsEmbeddedFacesAndMarginsPreservingEmphasisAndGenericFallback() throws {
        let css = "@font-face { font-family: 'Custom'; src: url('a}b.otf'); } @page { margin: 24px 0; } p { font-family: 'Custom', serif; font-weight: bold; font-style: italic; }"
        let result = try KindleFallbackCSS.normalize(css)
        XCTAssertFalse(result.css.contains("@"))
        XCTAssertFalse(result.css.contains("url"))
        XCTAssertTrue(result.css.contains("font-family: serif"))
        XCTAssertTrue(result.css.contains("font-weight: bold"))
        XCTAssertTrue(result.css.contains("font-style: italic"))
        XCTAssertEqual(result.warnings.count, 2)
    }
    func testInlineCustomAndGenericFamilies() throws {
        XCTAssertEqual(try KindleFallbackCSS.normalize("font-family: Custom; font-weight: 700").css, "font-family: serif; font-weight: 700")
        XCTAssertEqual(try KindleFallbackCSS.normalize("font-family:serif!important").css, "font-family:serif!important")
        XCTAssertEqual(try KindleFallbackCSS.normalize("font-family: sans-serif, monospace").css, "font-family: sans-serif, monospace")
        XCTAssertEqual(try KindleFallbackCSS.normalize("font-family: 'Custom', monospace !important").css, "font-family: monospace !important")
    }
    func testQuotedDelimitersAndComments() throws {
        let result = try KindleFallbackCSS.normalize("/* } */p { font-family: 'Semi; Brace}', serif; content: ';}'; }")
        XCTAssertTrue(result.css.contains("content: ';}'"))
        XCTAssertTrue(result.css.contains("font-family: serif"))
    }
    func testRejectsUnsafeAndMalformedCSS() {
        for css in ["p{background:url(x)}", "p{font-family:url(x)}", "p{font-family:expression(x)}", "@import 'a.css';", "@media print {p{color:red}}", "@page{size:A4}", "@page{@top-left{content:'x'}}", "p{font: italic 12px Custom}", "p{font-family:Custom", "p{color:'x}", "/* unterminated", "p{color:expre/**/ssion(x)}", "p{font-famil\\79:x}", "@font-face {src:url(x)", "p{color:red}}"] {
            XCTAssertThrowsError(try KindleFallbackCSS.normalize(css), css)
        }
    }
    func testBoundedInput() {
        XCTAssertThrowsError(try KindleFallbackCSS.normalize(String(repeating: " ", count: 1024 * 1024 + 1)))
    }
}
