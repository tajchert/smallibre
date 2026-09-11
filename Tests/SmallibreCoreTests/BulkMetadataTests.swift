import XCTest
@testable import SmallibreCore

final class BulkMetadataTests: XCTestCase, @unchecked Sendable {
    func library() async throws -> (URL, LibraryStore, [LibraryBook]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LibraryStore(root: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var books: [LibraryBook] = []
        for (name, ext) in [("Small Hours", "epub"), ("minimal", "mobi")] {
            books.append(try await store.importBook(from: Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!).book)
        }
        return (root, store, books)
    }
    func testPatchOnlyChangesChosenFieldsAndAddsTags() async throws {
        let (_, store, books) = try await library()
        var first = books[0]
        first.organization.tags = ["Existing"]
        try await store.update(first)
        var patch = BulkMetadataEdit()
        patch.authors = [" New Author "]
        patch.tags = .add(["New", "existing"])
        patch.isRead = true
        try await store.updateBooks(ids: books.map(\.id), edit: patch)
        let saved = try await store.books()
        for book in saved {
            let original = try XCTUnwrap(books.first { $0.id == book.id })
            XCTAssertEqual(book.metadata.title, original.metadata.title)
            XCTAssertEqual(book.metadata.publisher, original.metadata.publisher)
            XCTAssertEqual(book.metadata.authors, ["New Author"])
            XCTAssertTrue(book.organization.isRead)
            XCTAssertTrue(book.organization.tags.contains("New"))
            XCTAssertEqual(book.hash, original.hash)
        }
        XCTAssertEqual(saved.first { $0.id == first.id }?.organization.tags, ["Existing", "New"])
    }
    func testMissingBookAndInvalidEditLeaveWholeBatchUnchanged() async throws {
        let (_, store, books) = try await library()
        var patch = BulkMetadataEdit()
        patch.publisher = "Changed"
        do { try await store.updateBooks(ids: [books[0].id, UUID()], edit: patch); XCTFail("Missing book accepted") } catch {}
        var saved = try await store.books()
        XCTAssertEqual(Set(saved.map(\.metadata.publisher)), Set(books.map(\.metadata.publisher)))
        patch.series = .init(name: "Series", number: -1)
        do { try await store.updateBooks(ids: books.map(\.id), edit: patch); XCTFail("Invalid batch accepted") } catch {}
        saved = try await store.books()
        XCTAssertEqual(Set(saved.map(\.metadata.publisher)), Set(books.map(\.metadata.publisher)))
    }
    func testDatabaseFailureRollsBackEarlierBook() async throws {
        let (root, store, books) = try await library()
        let db = try Database(url: root.appendingPathComponent("library.sqlite"))
        try db.execute("CREATE TRIGGER fail_second BEFORE UPDATE ON books WHEN OLD.id = '\(books[1].id.uuidString)' BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        var patch = BulkMetadataEdit(); patch.language = "pl"
        do { try await store.updateBooks(ids: books.map(\.id), edit: patch); XCTFail("Expected trigger failure") } catch {}
        let saved = try await store.books()
        for book in saved { XCTAssertEqual(book, books.first { $0.id == book.id }) }
    }
    func testRemoveTagsAndExplicitlyClearSeries() async throws {
        let (_, store, books) = try await library()
        var book = books[0]
        book.organization = .init(tags: ["Keep", "Remove"], series: "Old", seriesNumber: 2)
        try await store.update(book)
        var patch = BulkMetadataEdit()
        patch.tags = .remove(["REMOVE"])
        patch.series = .init(name: "", number: nil)
        try await store.updateBooks(ids: [book.id], edit: patch)
        let saved = try await store.books().first { $0.id == book.id }!
        XCTAssertEqual(saved.organization.tags, ["Keep"])
        XCTAssertEqual(saved.organization.series, "")
        XCTAssertNil(saved.organization.seriesNumber)
    }
}
