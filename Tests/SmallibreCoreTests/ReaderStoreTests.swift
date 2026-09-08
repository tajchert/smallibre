import XCTest
@testable import SmallibreCore

final class ReaderStoreTests: XCTestCase, @unchecked Sendable {
    func testConnectedReaderScan() async throws {
        guard let path = ProcessInfo.processInfo.environment["SMALLIBRE_TEST_READER_SCAN"] else { throw XCTSkip("Opt-in device scan") }
        let books = try await ReaderStore(root: URL(fileURLWithPath: path)).scan()
        XCTAssertFalse(books.isEmpty)
        print("Device scan: \(books.count) files, \(books.filter { $0.metadata != nil }.count) with supported metadata")
    }
    func testScanDownloadAndGuardedDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let file = documents.appendingPathComponent("book.epub")
        try FileManager.default.copyItem(at: fixture, to: file)
        let reader = ReaderStore(root: documents)
        let books = try await reader.scan()
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        let library = try LibraryStore(root: root.appendingPathComponent("library"))
        let imported = try await reader.download(book, into: library)
        XCTAssertEqual(imported.book.hash, book.hash)
        let again = try await reader.download(book, into: library)
        XCTAssertTrue(again.isDuplicate)
        try Data("changed".utf8).write(to: file)
        do { try await reader.delete(book); XCTFail("Changed files must be preserved") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try Data(contentsOf: fixture).write(to: file)
        try await reader.delete(book)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let saved = try await library.books()
        XCTAssertEqual(saved.count, 1)
    }
    func testReplacementRootAndDirectoryArePreserved() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let file = root.appendingPathComponent("book.epub")
        try FileManager.default.copyItem(at: fixture, to: file)
        let reader = ReaderStore(root: root)
        let scan = try await reader.scan()
        let book = try XCTUnwrap(scan.first)
        try FileManager.default.moveItem(at: root, to: base.appendingPathComponent("old"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: file)
        do { try await reader.delete(book); XCTFail("Replacement root must be rejected") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let replacementReader = ReaderStore(root: root)
        let replacementScan = try await replacementReader.scan()
        let replacement = try XCTUnwrap(replacementScan.first)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let sentinel = file.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: sentinel)
        do { try await replacementReader.delete(replacement); XCTFail("Directory must be rejected") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }
    func testForeignConnectionAndSwappedParentAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("author")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let file = parent.appendingPathComponent("book.epub")
        try FileManager.default.copyItem(at: fixture, to: file)
        let first = ReaderStore(root: root), second = ReaderStore(root: root)
        let scan = try await first.scan()
        let book = try XCTUnwrap(scan.first)
        do { try await second.delete(book); XCTFail("Foreign record must fail") } catch {}
        do {
            try await first.delete(book, beforeUnlink: {
                try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("old"))
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: fixture, to: file)
            })
            XCTFail("Swapped parent must fail")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("old/book.epub").path))
    }
    func testOversizedFileDoesNotHideReadableBooks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("book.epub"))
        let large = root.appendingPathComponent("large.pdf")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(ZIPArchive.maximumSize + 1)); try handle.close()
        let books = try await ReaderStore(root: root).scan()
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books.filter { $0.metadata != nil }.count, 1)
        XCTAssertEqual(books.filter { $0.issue != nil }.count, 1)
    }
    func testScanSkipsSymlinksAndHiddenFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.epub"), withDestinationURL: fixture)
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent(".hidden.epub"))
        let books = try await ReaderStore(root: root).scan()
        XCTAssertTrue(books.isEmpty)
    }
}
