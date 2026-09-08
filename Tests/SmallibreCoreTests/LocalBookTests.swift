import XCTest
@testable import SmallibreCore

/// Opt-in compatibility check; personal books are never copied into test fixtures.
final class LocalBookTests: XCTestCase, @unchecked Sendable {
    func testLocalEPUBRoundTrip() async throws {
        guard let path = ProcessInfo.processInfo.environment["SMALLIBRE_TEST_EPUB"] else {
            throw XCTSkip("Set SMALLIBRE_TEST_EPUB to test a local book")
        }
        let source = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        var book = try await store.importBook(from: source).book
        let duplicate = try await store.importBook(from: source)
        XCTAssertTrue(duplicate.isDuplicate)
        let unchanged = try await store.preparedData(for: book.id)
        XCTAssertEqual(unchanged, original)
        let input = try EPUBBook(data: original)
        book.metadata.title += " — Smallibre test"
        book.typography = TypographySettings(enabled: input.allowsTypography, font: .serif)
        try await store.update(book)
        let outputURL = try await store.export(book.id, to: root)
        let output = try EPUBBook(data: Data(contentsOf: outputURL))
        XCTAssertEqual(output.metadata.title, book.metadata.title)
        XCTAssertEqual(output.chapters, input.chapters)
        for name in output.archive.names { _ = try output.archive.data(named: name) }
        for chapter in output.chapters {
            _ = try PreviewSanitizer.html(output.archive.data(named: chapter))
        }
        let reopened = try LibraryStore(root: root)
        let saved = try await reopened.books()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.metadata.title, book.metadata.title)
        XCTAssertEqual(try Data(contentsOf: source), original)
        print("Local EPUB verified: \(original.count) bytes, \(input.archive.names.count) resources, \(input.chapters.count) spine items; typography: \(input.allowsTypography)")
    }
}
