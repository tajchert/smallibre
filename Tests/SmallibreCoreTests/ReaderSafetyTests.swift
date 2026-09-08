import XCTest
@testable import SmallibreCore

final class ReaderSafetyTests: XCTestCase, @unchecked Sendable {
    func testBackupRequiredBeforeDeleteAndRestorable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let file = device.appendingPathComponent("book.epub")
        try FileManager.default.copyItem(at: fixture, to: file)
        let reader = ReaderStore(root: device)
        let items = try await reader.scan()
        let book = try XCTUnwrap(items.first)
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        do { _ = try await reader.backupAndDelete(book, localRoot: blocked); XCTFail("Backup failure must stop delete") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let backup = try await reader.backupAndDelete(book, localRoot: root.appendingPathComponent("local"))
        XCTAssertEqual(try Data(contentsOf: backup), try Data(contentsOf: fixture))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let receipt = try JSONDecoder().decode(ReaderReceipt.self, from: Data(contentsOf: backup.deletingLastPathComponent().appendingPathComponent("receipt.json")))
        XCTAssertEqual(receipt.state, "completed")
    }
    func testCacheReuseAndSidecarGrouping() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device"), cache = root.appendingPathComponent("cache.json")
        let assets = device.appendingPathComponent("book.sdr/assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: fixture, to: device.appendingPathComponent("book.epub"))
        try Data("component".utf8).write(to: assets.appendingPathComponent("resource.kfx"))
        let reader = ReaderStore(root: device)
        let first = try await reader.scan(cacheURL: cache)
        let second = try await reader.scan(cacheURL: cache)
        XCTAssertEqual(first.count, 1); XCTAssertEqual(second.count, 1)
        let reused = await reader.cachedCount
        XCTAssertEqual(reused, 1)
        try FileManager.default.removeItem(at: device.appendingPathComponent("book.epub"))
        let third = try await reader.scan(cacheURL: cache)
        XCTAssertTrue(third.isEmpty)
    }
}

extension ReaderSafetyTests {
    func testMetadataParentSwapPreservesExternalSentinel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device"), parent = device.appendingPathComponent("author"), outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "minimal", withExtension: "mobi", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: fixture, to: parent.appendingPathComponent("book.mobi"))
        let sentinel = outside.appendingPathComponent("book.mobi")
        try Data("sentinel".utf8).write(to: sentinel)
        let store = ReaderStore(root: device), scan = try await store.scan()
        let book = try XCTUnwrap(scan.first)
        var metadata = try XCTUnwrap(book.metadata); metadata.title = "Updated title"
        do {
            _ = try await store.updateMetadata(book, metadata: metadata, localRoot: root.appendingPathComponent("local"), beforeReplace: {
                try FileManager.default.moveItem(at: parent, to: device.appendingPathComponent("old"))
                try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)
            })
            XCTFail("Swapped directory must fail")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("sentinel".utf8))
        XCTAssertEqual(try Data(contentsOf: device.appendingPathComponent("old/book.mobi")), try Data(contentsOf: fixture))
    }
}

extension ReaderSafetyTests {
    func testSendExportsTheBackedUpSnapshotDespiteConcurrentLibraryEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device"), local = root.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let library = try LibraryStore(root: local)
        let book = try await library.importBook(from: fixture).book
        let output = try await ReaderStore(root: device).send(book.id, library: library, localRoot: local, beforeExport: {
            var edited = book; edited.metadata.title = "Changed during send"; try await library.update(edited)
        })
        let receipt = try XCTUnwrap(ReaderReceipt.list(localRoot: local).first)
        let sent = try Data(contentsOf: output)
        XCTAssertEqual(sent, try Data(contentsOf: receipt.backup))
        XCTAssertEqual(ReaderStore.digest(sent), receipt.sourceHash)
        XCTAssertEqual(try EPUBBook(data: sent).metadata.title, book.metadata.title)
    }
}

extension ReaderSafetyTests {
    func testInterruptedSendLeavesBackupAndReviewReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device"), local = root.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let library = try LibraryStore(root: local)
        let book = try await library.importBook(from: fixture).book
        do {
            _ = try await ReaderStore(root: device).send(book.id, library: library, localRoot: local, beforeExport: { throw CancellationError() })
            XCTFail("Interrupted send must fail")
        } catch {}
        let receipt = try XCTUnwrap(ReaderReceipt.list(localRoot: local).first)
        XCTAssertEqual(receipt.state, "needsReview")
        XCTAssertEqual(try Data(contentsOf: receipt.backup), try Data(contentsOf: fixture))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: device.path).isEmpty)
    }
}
