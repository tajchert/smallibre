import XCTest
@testable import NovaCore

final class RegressionTests: XCTestCase {
    func original() throws -> EPUBBook { try EPUBBook(data: Data(contentsOf: Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!)) }
    func testRejectsOverlappingZIPPayloadsBeforeDecompression() throws {
        let url = Bundle.module.url(forResource: "overlap", withExtension: "epub", subdirectory: "Fixtures")!
        XCTAssertThrowsError(try ZIPArchive(data: Data(contentsOf: url)))
    }
    func testTitleEditPreservesCreatorAttributesAndRefinements() throws {
        let source = try original()
        var opf = String(data: try source.archive.data(named: source.packagePath), encoding: .utf8)!
        opf = opf.replacingOccurrences(of: "<dc:creator>", with: "<dc:creator id=\"author1\">")
        opf = opf.replacingOccurrences(of: "</metadata>", with: "<meta refines=\"#author1\" property=\"role\" scheme=\"marc:relators\">aut</meta></metadata>")
        let book = try EPUBBook(data: source.archive.writing(replacements: [source.packagePath: Data(opf.utf8)]))
        var metadata = book.metadata; metadata.title = "Changed title"
        let output = try EPUBBook(data: EPUBEditor.prepare(book, metadata: metadata, typography: TypographySettings()))
        let document = try SafeXML.document(output.archive.data(named: output.packagePath))
        XCTAssertEqual(try document.nodes(forXPath: "//*[@id='author1']").first?.stringValue, "The Nova Studio")
        XCTAssertEqual(try document.nodes(forXPath: "//*[@refines='#author1']").first?.stringValue, "aut")
    }
    func testUTF16PackageIsParsedWithoutMismatchingDeclaration() throws {
        let source = try original()
        let opf = String(data: try source.archive.data(named: source.packagePath), encoding: .utf8)!.replacingOccurrences(of: "version=\"1.0\"", with: "version=\"1.0\" encoding=\"UTF-16\"")
        let book = try EPUBBook(data: source.archive.writing(replacements: [source.packagePath: opf.data(using: .utf16)!]))
        XCTAssertEqual(book.metadata.title, "Small Hours")
    }
    func testTypographyUsesXHTMLNamespaceInPrefixedChapter() throws {
        let source = try original()
        let html = "<h:html xmlns:h=\"http://www.w3.org/1999/xhtml\"><h:head><h:title>Chapter</h:title></h:head><h:body><h:p>Hello</h:p></h:body></h:html>"
        let book = try EPUBBook(data: source.archive.writing(replacements: [source.chapters[0]: Data(html.utf8)]))
        let result = try EPUBBook(data: EPUBEditor.prepare(book, metadata: book.metadata, typography: TypographySettings(enabled: true)))
        let document = try SafeXML.document(result.archive.data(named: source.chapters[0]))
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='style']").first?.uri, "http://www.w3.org/1999/xhtml")
    }
}
