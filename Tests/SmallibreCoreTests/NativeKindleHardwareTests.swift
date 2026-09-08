import XCTest
@testable import SmallibreCore

/// Opt-in physical test. Every mounted-device operation runs through the production helper.
/// It preserves existing files, deletes only its second disposable copy after backup, and leaves
/// the first native AZW3 for on-device reading. Keep its local receipts until hardware review ends.
final class NativeKindleHardwareTests: XCTestCase, @unchecked Sendable {
    func testNativeAZW3WithHelperTransferBackupMetadataAndDelete() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["SMALLIBRE_TEST_NATIVE_KINDLE"], let localPath = env["SMALLIBRE_TEST_NATIVE_KINDLE_LOCAL"] else {
            throw XCTSkip("Set SMALLIBRE_TEST_NATIVE_KINDLE and SMALLIBRE_TEST_NATIVE_KINDLE_LOCAL for authorized disposable testing")
        }
        let device = URL(fileURLWithPath: folder), local = URL(fileURLWithPath: localPath)
        guard !local.standardizedFileURL.path.hasPrefix("/Volumes/"),
              local.standardizedFileURL != device.standardizedFileURL else {
            throw BookError.invalid("Hardware test receipts must use a new folder on the Mac.")
        }
        guard !FileManager.default.fileExists(atPath: local.path) else { throw BookError.invalid("Use a new local folder for each hardware run.") }
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let fixture = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let epub = try Data(contentsOf: fixture), native = try AZW3PrototypeWriter.convert(epub)
        let nativeHash = SHA256Digest.digest(native).value
        let source = local.appendingPathComponent("authored-native.azw3")
        try native.write(to: source, options: .withoutOverwriting)
        let library = try LibraryStore(root: local)
        var imported = try await library.importBook(from: source).book
        imported.metadata.title = "Smallibre Native Test " + UUID().uuidString
        try await library.update(imported)

        func perform(_ request: ReaderRequest) async throws -> ReaderResponse {
            try await ReaderClient.perform(request, executable: helper, timeout: 60)
        }
        let connection = UUID()
        let initial = try await perform(ReaderRequest(action: "scan", root: device, connection: connection, rootIdentity: nil, localRoot: local, fullScan: true))
        let identity = try XCTUnwrap(initial.rootIdentity)
        let originalBooks = initial.books ?? []
        func checkPreserved(_ inventory: [ReaderBook]) {
            let byPath = Dictionary(uniqueKeysWithValues: inventory.map { ($0.relativePath, $0.hash) })
            for book in originalBooks { XCTAssertEqual(byPath[book.relativePath], book.hash, "Existing reader file changed") }
        }
        let sent = try await perform(ReaderRequest(action: "send", root: device, connection: connection, rootIdentity: identity, localRoot: local, libraryBookID: imported.id))
        let retained = try XCTUnwrap(sent.file)
        let afterSend = try await perform(ReaderRequest(action: "scan", root: device, connection: connection, rootIdentity: identity, localRoot: local, fullScan: true))
        let first = try XCTUnwrap(afterSend.books?.first { $0.relativePath == retained.lastPathComponent })
        XCTAssertEqual(first.hash, nativeHash)
        XCTAssertEqual(first.metadata?.format, "AZW3")
        XCTAssertEqual(first.metadata?.title, "Smallibre native Kindle proof")
        checkPreserved(afterSend.books ?? [])
        let copied = try await perform(ReaderRequest(action: "copy", root: device, connection: connection, rootIdentity: identity, book: first, localRoot: local))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copied.file)), native)
        let downloaded = try await perform(ReaderRequest(action: "download", root: device, connection: connection, rootIdentity: identity, book: first, localRoot: local))
        XCTAssertEqual(downloaded.imported?.id, imported.id, "Readback must deduplicate by bytes")

        // A new connection UUID simulates stale selection; this is not a physical unplug test.
        let freshConnection = UUID()
        do {
            _ = try await perform(ReaderRequest(action: "copy", root: device, connection: freshConnection, rootIdentity: identity, book: first, localRoot: local))
            XCTFail("An old selection must be rejected on a new connection")
        } catch { XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("stale")) }
        let secondSend = try await perform(ReaderRequest(action: "send", root: device, connection: freshConnection, rootIdentity: identity, localRoot: local, libraryBookID: imported.id))
        let disposable = try XCTUnwrap(secondSend.file)
        XCTAssertNotEqual(disposable, retained, "A second send must never overwrite the first")
        let beforeEdit = try await perform(ReaderRequest(action: "scan", root: device, connection: freshConnection, rootIdentity: identity, localRoot: local, fullScan: true))
        let second = try XCTUnwrap(beforeEdit.books?.first { $0.relativePath == disposable.lastPathComponent })
        var metadata = try XCTUnwrap(second.metadata)
        metadata.title = "Smallibre disposable metadata verification"
        let edited = try await perform(ReaderRequest(action: "metadata", root: device, connection: freshConnection, rootIdentity: identity, book: second, localRoot: local, metadata: metadata))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(edited.file)), native, "Metadata replacement must back up original bytes")
        let afterEdit = try await perform(ReaderRequest(action: "scan", root: device, connection: freshConnection, rootIdentity: identity, localRoot: local, fullScan: true))
        let editedBook = try XCTUnwrap(afterEdit.books?.first { $0.relativePath == disposable.lastPathComponent })
        XCTAssertEqual(editedBook.metadata?.title, metadata.title)
        let editedCopy = try await perform(ReaderRequest(action: "copy", root: device, connection: freshConnection, rootIdentity: identity, book: editedBook, localRoot: local))
        let editedBytes = try Data(contentsOf: XCTUnwrap(editedCopy.file))
        let count = Int(native.be16(76))
        XCTAssertEqual(Int(editedBytes.be16(76)), count)
        for record in 1..<count {
            let a = Int(native.be32(78 + record * 8)), b = record + 1 < count ? Int(native.be32(78 + (record + 1) * 8)) : native.count
            let c = Int(editedBytes.be32(78 + record * 8)), d = record + 1 < count ? Int(editedBytes.be32(78 + (record + 1) * 8)) : editedBytes.count
            XCTAssertEqual(native.subdata(in: a..<b), editedBytes.subdata(in: c..<d), "Metadata edit changed a content record")
        }
        let deleted = try await perform(ReaderRequest(action: "delete", root: device, connection: freshConnection, rootIdentity: identity, book: editedBook, localRoot: local))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(deleted.file)), editedBytes)
        let final = try await perform(ReaderRequest(action: "scan", root: device, connection: freshConnection, rootIdentity: identity, localRoot: local, fullScan: true))
        XCTAssertFalse(final.books?.contains { $0.relativePath == disposable.lastPathComponent } ?? true)
        XCTAssertEqual(final.books?.first { $0.relativePath == retained.lastPathComponent }?.hash, nativeHash)
        XCTAssertEqual(final.books?.count, originalBooks.count + 1)
        checkPreserved(final.books ?? [])
        XCTAssertEqual(try Data(contentsOf: fixture), epub)
        XCTAssertEqual(try Data(contentsOf: source), native)
        let receipts = ReaderReceipt.list(localRoot: local)
        XCTAssertEqual(receipts.count, 6)
        XCTAssertTrue(receipts.allSatisfy { $0.state == "completed" })
        let evidence: [String: String] = ["retainedDeviceFile": retained.path, "localRoot": local.path,
            "nativeSHA256": nativeHash, "initialBooks": String(originalBooks.count), "finalBooks": String(final.books?.count ?? -1),
            "receiptCount": String(receipts.count), "readingConfirmed": "false"]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: local.appendingPathComponent("hardware-result.json"), options: .withoutOverwriting)
        print("Native Kindle helper checks complete; \(originalBooks.count) existing books preserved; six verified receipts. Retained for reading: \(retained.lastPathComponent)")
    }
}
