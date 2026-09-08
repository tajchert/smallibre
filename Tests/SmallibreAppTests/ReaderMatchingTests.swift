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
        model.books = [book]; model.filter = "device"
        model.reader.books = [ReaderBook(connection: model.reader.generation, relativePath: "book.azw3",
                                         metadata: book.metadata, hash: outputHash.value, byteCount: 24, issue: nil)]
        model.reader.selectedIDs = ["book.azw3"]
        model.reader.receipts = [receipt]
        XCTAssertNil(model.selected)
        XCTAssertNil(model.reader.libraryMatch(book, deviceHash: outputHash.value))
        XCTAssertNil(model.reader.libraryBook(deviceHash: outputHash.value, library: [book]))
        try record.uploaded(.init(destination: destination, locator: .mounted(relativePath: "book.azw3")))
        record.verified(); receipt.transfer = record; receipt.state = "verified"
        model.reader.receipts = [receipt]
        XCTAssertEqual(model.selected?.id, book.id)
        XCTAssertEqual(model.reader.libraryMatch(book, deviceHash: outputHash.value), .converted)
        XCTAssertEqual(model.reader.libraryBook(deviceHash: outputHash.value, library: [book])?.id, book.id)
        XCTAssertEqual(model.reader.libraryBook(deviceHash: book.hash, library: [book])?.id, book.id)
        XCTAssertNil(model.reader.libraryBook(deviceHash: nil, library: [book]))
        XCTAssertNil(model.reader.libraryBook(deviceHash: "", library: [book]))
        var importedAZW3 = book
        importedAZW3.id = UUID(); importedAZW3.hash = outputHash.value
        XCTAssertEqual(model.reader.libraryBook(deviceHash: outputHash.value, library: [book, importedAZW3])?.id, importedAZW3.id)

        XCTAssertEqual(model.reader.libraryMatch(book, deviceHash: book.hash), .original)
        XCTAssertNil(model.reader.libraryMatch(book, deviceHash: ""))
        XCTAssertNil(model.reader.libraryMatch(book, deviceHash: SHA256Digest.digest(Data("different bytes".utf8)).value))
        var changedOriginal = book
        changedOriginal.hash = SHA256Digest.digest(Data("replacement original".utf8)).value
        XCTAssertNil(model.reader.libraryMatch(changedOriginal, deviceHash: outputHash.value))
        XCTAssertNil(model.reader.libraryBook(deviceHash: outputHash.value, library: [changedOriginal]))
        var sameTitle = book
        sameTitle.id = UUID()
        XCTAssertNil(model.reader.libraryMatch(sameTitle, deviceHash: outputHash.value))
    }
}
