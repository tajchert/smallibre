import XCTest
@testable import SmallibreCore

final class LibraryTests: XCTestCase, @unchecked Sendable {
    func fixture() -> URL { Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")! }
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testImportDeduplicatesBytesAndSurvivesDatabaseReopen() async throws {
        let folder = try root(), store = try LibraryStore(root: folder)
        let first = try await store.importBook(from: fixture())
        let second = try await store.importBook(from: fixture())
        XCTAssertEqual(first.book.id, second.book.id)
        XCTAssertTrue(second.isDuplicate)
        let reopened = try LibraryStore(root: folder)
        let books = try await reopened.books()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].metadata.title, "Small Hours")
    }
    func testMetadataAndTypographyExportNeverMutateOriginal() async throws {
        let folder = try root(), store = try LibraryStore(root: folder)
        let sourceBytes = try Data(contentsOf: fixture())
        var book = try await store.importBook(from: fixture()).book
        book.metadata.title = "My Small Hours"
        book.typography = TypographySettings(enabled: true, font: .serif, lineHeight: 1.8, marginPercent: 6)
        try await store.update(book)
        let prepared = try await store.preparedData(for: book.id)
        let output = try EPUBBook(data: prepared)
        XCTAssertEqual(output.metadata.title, "My Small Hours")
        let html = String(data: try output.archive.data(named: "EPUB/chapter1.xhtml"), encoding: .utf8)!
        XCTAssertTrue(html.contains("line-height: 1.8"))
        XCTAssertTrue(html.contains("A book asks for very little"))
        let original = try await store.originalURL(for: book.id)
        XCTAssertEqual(try Data(contentsOf: original), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: fixture()), sourceBytes)
    }
    /// A read-only metadata field must never decide that a book was edited. A record saved before
    /// the field existed decodes without it, so its value differs from the file's; the book still
    /// has to export its original bytes.
    func testReadOnlyMetadataDifferenceKeepsOriginalBytes() async throws {
        let folder = try root(), store = try LibraryStore(root: folder)
        let sourceBytes = try Data(contentsOf: fixture())
        let book = try await store.importBook(from: fixture()).book
        var prepared = try await store.preparedData(for: book.id)
        XCTAssertEqual(prepared, sourceBytes)
        // Rewrite the stored record behind the store, the only way this mismatch arises in practice.
        let database = try Database(url: folder.appendingPathComponent("library.sqlite"))
        var stored = try XCTUnwrap(database.book(column: "id", value: book.id.uuidString))
        stored.metadata.published = "1999-01-01"
        try database.save(stored, insert: false)
        prepared = try await store.preparedData(for: book.id)
        XCTAssertEqual(prepared, sourceBytes)
    }
    func testExportAvoidsOverwritingExistingFiles() async throws {
        let folder = try root(), destination = try root(), store = try LibraryStore(root: folder)
        let book = try await store.importBook(from: fixture()).book
        let first = try await store.export(book.id, to: destination)
        let original = try Data(contentsOf: first)
        let second = try await store.export(book.id, to: destination)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), original)
        XCTAssertEqual(try Data(contentsOf: second), original)
    }
    func testZIPRoundTripRetainsUnchangedContent() throws {
        let epub = try EPUBBook(data: Data(contentsOf: fixture()))
        let output = try ZIPArchive(data: epub.archive.writing(replacements: [:]))
        XCTAssertEqual(try output.data(named: "EPUB/chapter1.xhtml"), try epub.archive.data(named: "EPUB/chapter1.xhtml"))
        XCTAssertEqual(output.names.first, "mimetype")
    }
    func testUnsupportedTypographyIsRejectedBeforeChangingLibrary() async throws {
        let folder = try root(), store = try LibraryStore(root: folder)
        let source = try EPUBBook(data: Data(contentsOf: fixture()))
        let opf = String(data: try source.archive.data(named: source.packagePath), encoding: .utf8)!.replacingOccurrences(of: "</metadata>", with: "<meta property=\"rendition:layout\">pre-paginated</meta></metadata>")
        let file = folder.appendingPathComponent("fixed.epub")
        try source.archive.writing(replacements: [source.packagePath: Data(opf.utf8)]).write(to: file)
        var book = try await store.importBook(from: file).book
        book.typography.enabled = true
        do { try await store.update(book); XCTFail("Fixed-layout typography must not be saved") } catch {}
        let saved = try await store.books()
        XCTAssertFalse(saved[0].typography.enabled)
        _ = try await store.preparedData(for: book.id)
    }
}
