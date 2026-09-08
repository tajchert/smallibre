import XCTest
@testable import SmallibreCore

final class MetadataTests: XCTestCase {
    func testMetadataResultsPreserveMultipleAuthorsAndSkipIncompleteResults() throws {
        let json = Data(#"{"docs":[{"key":"/works/OL1W","title":"A Book","author_name":["Author One","Author Two"],"first_publish_year":2020},{"key":"/works/OL2W"},{"key":"/works/OL1W","title":"Duplicate"}]}"#.utf8)
        let results = try MetadataLookup.decode(json)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "A Book")
        XCTAssertEqual(results.first?.authors, ["Author One", "Author Two"])
        XCTAssertEqual(results.first?.firstPublished, 2020)
    }
    func testRejectsOversizedMetadataResponses() {
        XCTAssertThrowsError(try MetadataLookup.decode(Data(repeating: 32, count: 2_000_001)))
    }
}
