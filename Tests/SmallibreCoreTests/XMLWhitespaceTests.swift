import XCTest
import Foundation
@testable import SmallibreCore

final class XMLWhitespaceTests: XCTestCase {
    func testPreservesSpacesBetweenInlineElementsWithExternalDoctype() throws {
        let declaration = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
        for doctype in ["", declaration] {
            let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\(doctype)<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Authored</title></head><body><p><span>First</span> <span>second</span> <em>third</em></p><p><span>A</span>\n<span>B</span></p></body></html>"
            let document = try SafeXML.document(Data(xml.utf8), preservingTextWhitespace: true)
            let paragraphs = try document.nodes(forXPath: "//*[local-name()='p']")
            XCTAssertEqual(paragraphs[0].stringValue, "First second third")
            XCTAssertEqual(paragraphs[1].stringValue, "A\nB")
        }
    }
    func testWhitespacePassPreservesMarkupAndLineEndingSemantics() throws {
        let xml = "\n<?authored probe?>\n<!DOCTYPE html><html><p title=\"a > b\"><span>A</span> \r\n\t<span>B</span><!-- > [ --> <![CDATA[ ]]><span>C</span><?probe value?> </p></html>\n"
        let document = try SafeXML.document(Data(xml.utf8), preservingTextWhitespace: true)
        let paragraph = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='p']").first)
        XCTAssertEqual(try paragraph.nodes(forXPath: ".//text()").compactMap(\.stringValue).joined(), "A \n\tB  C ")
        XCTAssertEqual((paragraph as? XMLElement)?.attribute(forName: "title")?.stringValue, "a > b")
    }
    func testWhitespacePassAcceptsUTF16AndKeepsEntityProtection() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><p><span>A</span> <span>B</span></p>"
        let document = try SafeXML.document(try XCTUnwrap(xml.data(using: .utf16)), preservingTextWhitespace: true)
        XCTAssertEqual(document.rootElement()?.stringValue, "A B")
        XCTAssertThrowsError(try SafeXML.document(Data("<!DOCTYPE p [<!-- ] > -->]><p/>".utf8), preservingTextWhitespace: true))
        XCTAssertThrowsError(try SafeXML.document(Data("<!DOCTYPE p [<!ENTITY x 'unsafe'>]><p>&x;</p>".utf8), preservingTextWhitespace: true))
    }

    func testConversionAndTypographyKeepInlineWordSeparators() throws {
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let archive = try ZIPArchive(data: Data(contentsOf: source))
        let path = "Book/text/one.xhtml"
        let html = String(decoding: try archive.data(named: path), as: UTF8.self)
            .replacingOccurrences(of: "</body>", with: "<p><span>Keep</span> <span>space</span></p></body>")
        let original = try archive.writing(replacements: [path: Data(html.utf8)])
        let epub = try EPUBBook(data: original)
        let edited = try EPUBEditor.prepare(epub, metadata: epub.metadata, typography: TypographySettings(enabled: true))
        for data in [original, edited] {
            let document = try AZW3PrototypeDocument(data, production: true)
            XCTAssertTrue(document.chapters[0].body.contains("</span> <span"))
            _ = try AZW3Converter.convert(data)
        }
    }
    func testWhitespaceExpansionRemainsBounded() {
        let xml = "<p>" + String(repeating: " ", count: 1500000) + "</p>"
        XCTAssertThrowsError(try SafeXML.document(Data(xml.utf8), preservingTextWhitespace: true))
    }

}
