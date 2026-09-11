import XCTest
@testable import SmallibreCore

final class LibraryOrganizationTests: XCTestCase, @unchecked Sendable {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private var fixture: URL { Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")! }

    func testLegacyRecordDefaultsToUnreadWithoutOrganization() async throws {
        let store = try LibraryStore(root: root())
        let book = try await store.importBook(from: fixture).book
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        json.removeValue(forKey: "organization")
        let legacy = try JSONDecoder().decode(LibraryBook.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.organization, BookOrganization())
    }

    func testOrganizationPersistsNormalizedAndKeepsExportBytes() async throws {
        let folder = try root(), store = try LibraryStore(root: folder)
        var book = try await store.importBook(from: fixture).book
        book.organization = BookOrganization(tags: [" Fiction ", "fiction", "", "Night"], series: " Stories ", seriesNumber: 1.5, isRead: true)
        try await store.update(book)
        let reopened = try LibraryStore(root: folder)
        let saved = try await reopened.books()[0]
        XCTAssertEqual(saved.organization.tags, ["Fiction", "Night"])
        XCTAssertEqual(saved.organization.series, "Stories")
        XCTAssertEqual(saved.organization.seriesNumber, 1.5)
        XCTAssertTrue(saved.organization.isRead)
        let prepared = try await reopened.preparedData(for: book.id)
        XCTAssertEqual(prepared, try Data(contentsOf: fixture))
    }

    func testInvalidSeriesNumberDoesNotSaveOtherChanges() async throws {
        let store = try LibraryStore(root: root())
        let original = try await store.importBook(from: fixture).book
        for number in [-1.0, Double.infinity, Double.nan] {
            var book = original
            book.metadata.title = "Should not be saved"
            book.organization = BookOrganization(series: "Stories", seriesNumber: number)
            do { try await store.update(book); XCTFail("Invalid sequence accepted") } catch {}
            let saved = try await store.books()[0]
            XCTAssertEqual(saved, original)
        }
    }
}
