import XCTest
@testable import SmallibreCore

final class MountedReaderTransportTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> (URL, URL, ReaderDestination) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let root = base.appendingPathComponent("reader")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ReaderStore(root: root)
        return (base, root, ReaderDestination(connection: UUID(), endpoint: .mounted(root: root, rootIdentity: try XCTUnwrap(store.rootIdentity))))
    }
    func testStoredArtifactTransferRecordsVerificationAndRejectsCorruption() async throws {
        let (base, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let local = base.appendingPathComponent("library")
        let library = try LibraryStore(root: local)
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let book = try await library.importBook(from: source).book
        let artifact = try await library.prepareKindleArtifact(for: book.id)
        let bytes = try artifact.verifiedData()
        let store = ReaderStore(root: root)
        let target = try await store.sendArtifact(artifact, localRoot: local)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        let receipt = try XCTUnwrap(ReaderReceipt.list(localRoot: local).first)
        XCTAssertEqual(receipt.transfer?.state, .verified)
        XCTAssertEqual(receipt.transfer?.artifact, artifact)
        XCTAssertEqual(try Data(contentsOf: receipt.backup), bytes)
        try Data(repeating: 0, count: bytes.count).write(to: artifact.localURL)
        do { _ = try await store.sendArtifact(artifact, localRoot: local); XCTFail("Corrupt artifact must not upload") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [artifact.suggestedFilename])
        XCTAssertEqual(ReaderReceipt.list(localRoot: local).count, 1)
    }
    func testHelperTransfersStoredArtifactAndRejectsStaleRoot() async throws {
        let (base, root, destination) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let local = base.appendingPathComponent("library"), library = try LibraryStore(root: local)
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let book = try await library.importBook(from: source).book
        let artifact = try await library.prepareKindleArtifact(for: book.id)
        guard case let .mounted(_, identity) = destination.endpoint else { return XCTFail("Mounted fixture") }
        let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let request = ReaderRequest(action: "sendArtifact", root: root, connection: destination.connection,
            rootIdentity: identity, localRoot: local, preparedArtifact: artifact)
        let response = try await ReaderClient.perform(request, executable: helper)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(response.file)), try artifact.verifiedData())
        XCTAssertEqual(ReaderReceipt.list(localRoot: local).first?.transfer?.state, .verified)
        try FileManager.default.moveItem(at: root, to: base.appendingPathComponent("old-reader"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do { _ = try await ReaderClient.perform(request, executable: helper); XCTFail("Stale root must fail") } catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testCollisionsAndSymlinksArePreservedAndReadbackIsExact() async throws {
        let (base, root, destination) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let original = Data("existing".utf8), bytes = Data("new captured bytes".utf8)
        let existing = root.appendingPathComponent("Book.azw3")
        try original.write(to: existing)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Book (1).azw3"), withDestinationURL: existing)
        let transport = try MountedReaderTransport(destination: destination)
        let item = try await transport.uploadNew(bytes, suggestedFilename: "Book.azw3", to: destination)
        XCTAssertEqual(item.locator, .mounted(relativePath: "Book (2).azw3"))
        let local = base.appendingPathComponent("readback")
        try await transport.fetch(item, to: local, maximumBytes: bytes.count)
        XCTAssertEqual(try Data(contentsOf: local), bytes)
        XCTAssertEqual(try Data(contentsOf: existing), original)
        do { try await transport.fetch(item, to: local, maximumBytes: bytes.count); XCTFail("Must not overwrite local file") } catch {}
        XCTAssertEqual(try Data(contentsOf: local), bytes)
    }
    func testRootReplacementBeforeCreationWritesNeitherFolder() async throws {
        let (base, root, destination) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let moved = base.appendingPathComponent("old-reader")
        let transport = try MountedReaderTransport(destination: destination, beforeCreate: {
            try FileManager.default.moveItem(at: root, to: moved)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        })
        do { _ = try await transport.uploadNew(Data("bytes".utf8), suggestedFilename: "Book.azw3", to: destination); XCTFail("Replaced root must fail") } catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }
    func testFetchRejectsOversizeAndSymlinkObjects() async throws {
        let (base, root, destination) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let transport = try MountedReaderTransport(destination: destination)
        let item = try await transport.uploadNew(Data("bytes".utf8), suggestedFilename: "Book.azw3", to: destination)
        do { try await transport.fetch(item, to: base.appendingPathComponent("small"), maximumBytes: 2); XCTFail("Oversized object") } catch {}
        try FileManager.default.removeItem(at: root.appendingPathComponent("Book.azw3"))
        let outside = base.appendingPathComponent("outside")
        try Data("bytes".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Book.azw3"), withDestinationURL: outside)
        do { try await transport.fetch(item, to: base.appendingPathComponent("link"), maximumBytes: 5); XCTFail("Symlink object") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("link").path))
    }
}
