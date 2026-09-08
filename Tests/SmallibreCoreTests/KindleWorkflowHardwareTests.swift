import XCTest
@testable import SmallibreCore

/// Opt-in, authored copies only. No deletion or changes to existing books.
final class KindleWorkflowHardwareTests: XCTestCase, @unchecked Sendable {
    func testPreparedEPUBWorkflowOnMountedKindle() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let devicePath = env["SMALLIBRE_TEST_KINDLE_WORKFLOW"], let localPath = env["SMALLIBRE_TEST_KINDLE_WORKFLOW_LOCAL"] else {
            throw XCTSkip("Set SMALLIBRE_TEST_KINDLE_WORKFLOW and a fresh SMALLIBRE_TEST_KINDLE_WORKFLOW_LOCAL for authorized authored-copy testing")
        }
        let device = URL(fileURLWithPath: devicePath), local = URL(fileURLWithPath: localPath)
        guard !local.standardizedFileURL.path.hasPrefix("/Volumes/"), !FileManager.default.fileExists(atPath: local.path) else {
            throw BookError.invalid("Use a new local folder on the Mac.")
        }
        let library = try LibraryStore(root: local)
        let source = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let original = try Data(contentsOf: source)
        var book = try await library.importBook(from: source).book
        book.metadata.title = "Smallibre EPUB workflow " + String(UUID().uuidString.prefix(8))
        book.typography = TypographySettings(enabled: true, font: .serif, lineHeight: 1.8, marginPercent: 5)
        try await library.update(book)
        let artifact = try await library.prepareKindleArtifact(for: book.id)
        let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let connection = UUID()
        let before = try await ReaderClient.perform(ReaderRequest(action: "scan", root: device, connection: connection,
            rootIdentity: nil, localRoot: local, fullScan: true), executable: helper, timeout: 60)
        let identity = try XCTUnwrap(before.rootIdentity)
        let sent = try await ReaderClient.perform(ReaderRequest(action: "sendArtifact", root: device, connection: connection,
            rootIdentity: identity, localRoot: local, libraryBookID: book.id, preparedArtifact: artifact), executable: helper, timeout: 60)
        let output = try XCTUnwrap(sent.file)
        let after = try await ReaderClient.perform(ReaderRequest(action: "scan", root: device, connection: connection,
            rootIdentity: identity, localRoot: local, fullScan: true), executable: helper, timeout: 60)
        let byPath = Dictionary(uniqueKeysWithValues: (after.books ?? []).map { ($0.relativePath, $0.hash) })
        for existing in before.books ?? [] { XCTAssertEqual(byPath[existing.relativePath], existing.hash) }
        XCTAssertEqual(after.books?.count, (before.books?.count ?? 0) + 1)
        XCTAssertEqual(byPath[output.lastPathComponent], artifact.outputSHA256.value)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let receipts = ReaderReceipt.list(localRoot: local)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.transfer?.state, .verified)
        XCTAssertEqual(receipts.first?.transfer?.artifact, artifact)
        print("Retained authored workflow test: \(output.lastPathComponent). Artifact: \(artifact.localURL.path). Rendering is not yet confirmed.")
    }
}
