import XCTest
@testable import SmallibreCore

final class LibraryQueryTests: XCTestCase, @unchecked Sendable {
    func book() -> LibraryBook {
        LibraryBook(id: UUID(), metadata: .init(title: "Small Hours", authors: ["Zoë Writer"], language: "en", identifier: "9781234567890", publisher: "Moon Press", description: "A quiet journey", format: "EPUB", cover: nil), addedAt: Date(), byteCount: 1, originalFilename: "sample.epub", hash: "sample", typography: .init(), organization: .init(tags: ["Fiction"], series: "Night Stories", seriesNumber: 2, isRead: true))
    }
    func testSearchMatchesWordsAcrossFieldsWithCaseAndDiacriticFolding() {
        let book = book()
        for text in ["zoe MOON", "978123", "journey", "fiction stories", "  small   quiet  "] {
            XCTAssertTrue(LibraryQuery(text: text).matches(book), text)
        }
        XCTAssertFalse(LibraryQuery(text: "small missing").matches(book))
        XCTAssertTrue(LibraryQuery(text: " \n ").matches(book))
    }
    func testFiltersCombineAndUseExactTagsAndSeries() {
        let book = book()
        XCTAssertTrue(LibraryQuery(collection: "EPUB", readState: .read, tag: "fiction", series: "night stories").matches(book))
        XCTAssertFalse(LibraryQuery(readState: .unread).matches(book))
        XCTAssertFalse(LibraryQuery(tag: "Fict").matches(book))
        XCTAssertFalse(LibraryQuery(collection: "MOBI").matches(book))
        XCTAssertFalse(LibraryQuery(collection: "prepared").matches(book))
    }
    func testSavedFiltersSurviveReopenAndDeletionAndRejectBlankName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        let filter = SavedLibraryFilter(name: "Night reading", query: .init(text: "night", collection: "EPUB", readState: .unread, tag: "Fiction"))
        try await store.saveFilter(filter)
        let reopened = try LibraryStore(root: root)
        let saved = try await reopened.savedFilters()
        XCTAssertEqual(saved, [filter])
        do { try await store.saveFilter(.init(name: "  ", query: .init())); XCTFail("Blank name accepted") } catch {}
        try await reopened.deleteFilter(id: filter.id)
        let remaining = try await store.savedFilters()
        XCTAssertTrue(remaining.isEmpty)
    }
    func testStoreSearchUsesExpandedFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        var book = try await store.importBook(from: Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!).book
        book.organization.tags = ["UniqueTag"]
        book.metadata.publisher = "UniquePublisher"
        try await store.update(book)
        let matches = try await store.books(search: "uniquetag uniquepublisher")
        XCTAssertEqual(matches.map(\.id), [book.id])
    }
}
