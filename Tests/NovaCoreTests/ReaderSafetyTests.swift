import XCTest
@testable import NovaCore

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
