import XCTest
@testable import SmallibreCore

final class ReaderTransferTests: XCTestCase, @unchecked Sendable {
    func testMountedReaderRoundTrip() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let sourcePath = env["SMALLIBRE_TEST_READER_BOOK"], let folderPath = env["SMALLIBRE_TEST_READER_FOLDER"] else {
            throw XCTSkip("Set SMALLIBRE_TEST_READER_BOOK and SMALLIBRE_TEST_READER_FOLDER for an authorized hardware test")
        }
        let source = URL(fileURLWithPath: sourcePath)
        let folder = URL(fileURLWithPath: folderPath)
        let original = try Data(contentsOf: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        var book = try await store.importBook(from: source).book
        XCTAssertTrue(["MOBI", "AZW3"].contains(book.metadata.format))
        book.metadata.title = "Smallibre transfer test " + UUID().uuidString
        try await store.update(book)
        let first = try await store.export(book.id, to: folder)
        defer { try? FileManager.default.removeItem(at: first) }
        XCTAssertEqual(try Data(contentsOf: first), original)
        let second = try await store.export(book.id, to: folder)
        defer { try? FileManager.default.removeItem(at: second) }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: second), original)
        XCTAssertEqual(try Data(contentsOf: first), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        print("Reader round trip verified: \(original.count) bytes, \(book.metadata.format), two collision-safe exports")
    }
}
