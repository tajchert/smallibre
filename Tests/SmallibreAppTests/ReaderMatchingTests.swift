import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class ReaderMatchingTests: XCTestCase {
    func testConvertedMatchRequiresVerifiedBytesAndOriginalProvenance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        let outputHash = SHA256Digest.digest(Data("authored converted bytes".utf8))
        let originalHash = try SHA256Digest(book.hash)
        let artifact = try PreparedBookArtifact(id: UUID(), provenance: .init(sourceLibraryID: book.id,
            sourceOriginalSHA256: originalHash, preparedInputSHA256: originalHash, settingsSHA256: originalHash,
            converterVersion: "test", profile: "test"), outputFormat: .azw3, suggestedFilename: "book.azw3",
            localURL: root.appendingPathComponent("book.azw3"), byteCount: 24, outputSHA256: outputHash, warnings: [])
        let destination = ReaderDestination(connection: UUID(), endpoint: .mounted(root: root, rootIdentity: "fixture"))
        var record = ReaderTransferRecord(artifact: artifact, destination: destination)
        var receipt = ReaderReceipt(id: record.id, operation: "sendArtifact", source: "book.azw3", sourceHash: outputHash.value,
            backup: root.appendingPathComponent("backup.azw3"), date: Date(), state: "intent", transfer: record)
        model.reader.receipts = [receipt]
        XCTAssertNil(model.reader.libraryMatch(book, deviceHash: outputHash.value))
        try record.uploaded(.init(destination: destination, locator: .mounted(relativePath: "book.azw3")))
        record.verified(); receipt.transfer = record; receipt.state = "verified"
        model.reader.receipts = [receipt]
        XCTAssertEqual(model.reader.libraryMatch(book, deviceHash: outputHash.value), .converted)
        XCTAssertEqual(model.reader.libraryMatch(book, deviceHash: book.hash), .original)
        XCTAssertNil(model.reader.libraryMatch(book, deviceHash: ""))
        XCTAssertNil(model.reader.libraryMatch(book, deviceHash: SHA256Digest.digest(Data("different bytes".utf8)).value))
        var changedOriginal = book
        changedOriginal.hash = SHA256Digest.digest(Data("replacement original".utf8)).value
        XCTAssertNil(model.reader.libraryMatch(changedOriginal, deviceHash: outputHash.value))
        var sameTitle = book
        sameTitle.id = UUID()
        XCTAssertNil(model.reader.libraryMatch(sameTitle, deviceHash: outputHash.value))
    }
}
