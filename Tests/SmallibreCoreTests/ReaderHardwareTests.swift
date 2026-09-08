import XCTest
@testable import SmallibreCore

final class ReaderHardwareTests: XCTestCase, @unchecked Sendable {
    func testDisposableMetadataAndBackedUpDelete() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let devicePath = env["SMALLIBRE_HARDWARE_DEVICE"], let sourcePath = env["SMALLIBRE_HARDWARE_SOURCE"], let localPath = env["SMALLIBRE_HARDWARE_LOCAL"] else { throw XCTSkip("Opt-in disposable hardware workflow") }
        let root = URL(fileURLWithPath: devicePath), local = URL(fileURLWithPath: localPath)
        let original = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        var metadata = try MOBIBook.inspect(original)
        metadata.title = "Smallibre Reader Test — delete check"
        let prepared = try MOBIMetadataEditor.prepare(original, metadata: metadata)
        let name = "Smallibre Reader Test \(UUID().uuidString).mobi"
        let target = root.appendingPathComponent(name)
        try prepared.write(to: target, options: .withoutOverwriting)
        let store = ReaderStore(root: root)
        let scanned = try await store.scan()
        let book = try XCTUnwrap(scanned.first { $0.relativePath == name })
        let backup = try await store.backupAndDelete(book, localRoot: local)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: backup), prepared)
        metadata.title = "Smallibre Reader Test — before update"
        try MOBIMetadataEditor.prepare(original, metadata: metadata).write(to: target, options: .withoutOverwriting)
        let rescanned = try await store.scan()
        let copied = try XCTUnwrap(rescanned.first { $0.relativePath == name })
        metadata.title = "Smallibre Reader Test — ready to read"
        _ = try await store.updateMetadata(copied, metadata: metadata, localRoot: local)
        let result = try Data(contentsOf: target)
        XCTAssertEqual(try MOBIBook.inspect(result).title, metadata.title)
        let oldCount = Int(original.be16(76)), newCount = Int(result.be16(76))
        XCTAssertEqual(oldCount, newCount)
        for index in 1..<oldCount {
            let a = Int(original.be32(78 + index * 8)), b = index + 1 < oldCount ? Int(original.be32(78 + (index + 1) * 8)) : original.count
            let c = Int(result.be32(78 + index * 8)), d = index + 1 < newCount ? Int(result.be32(78 + (index + 1) * 8)) : result.count
            XCTAssertEqual(original.subdata(in: a..<b), result.subdata(in: c..<d))
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: sourcePath)), original)
        print("Disposable delete and metadata update verified; left for screen check: \(target.path)")
    }
}
