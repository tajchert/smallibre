import XCTest
@testable import NovaCore

final class BookEngineTests: XCTestCase {
    func fixture(_ name: String) -> URL { Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")! }

    func testExtractsNamespacedEPUBMetadataAndDeflatedResources() throws {
        let book = try BookInspector.inspect(fixture("Small Hours.epub"))
        XCTAssertEqual(book.title, "Small Hours")
        XCTAssertEqual(book.authors, ["The Nova Studio"])
        XCTAssertEqual(book.language, "en")
        XCTAssertEqual(book.identifier, "urn:uuid:nova-small-hours")
        XCTAssertEqual(book.format, "EPUB")
    }

    func testRejectsArchiveTraversalRatherThanExtractingIt() {
        XCTAssertThrowsError(try BookInspector.inspect(fixture("unsafe.epub")))
    }

    func testSniffsContentRatherThanTrustingExtension() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mobi")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.copyItem(at: fixture("Small Hours.epub"), to: temp)
        XCTAssertEqual(try BookInspector.inspect(temp).format, "EPUB")
    }

    func testReadsMOBITitleAndEXTHAuthor() throws {
        let book = try BookInspector.inspect(fixture("minimal.mobi"))
        XCTAssertEqual(book.title, "A Pocket Library")
        XCTAssertEqual(book.authors, ["Nova Studio"])
        XCTAssertEqual(book.format, "MOBI")
    }

    func testRejectsTruncatedMOBI() {
        XCTAssertThrowsError(try BookInspector.inspect(fixture("truncated.mobi")))
    }
}
