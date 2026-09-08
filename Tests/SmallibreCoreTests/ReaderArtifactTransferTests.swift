import XCTest
@testable import SmallibreCore

final class ReaderArtifactTransferTests: XCTestCase, @unchecked Sendable {
    func testVerifiedTransferPersistsExactProvenanceAndReadback() async throws {
        let f = try ArtifactFixture(); defer { f.remove() }
        let transport = FakeReaderTransport()
        let journal = TransferJournal(root: f.root)
        let record = try await send(f, transport, journal)
        XCTAssertEqual(record.state, .verified)
        XCTAssertEqual(record.artifact.outputSHA256, SHA256Digest.digest(f.bytes))
        XCTAssertEqual(record.artifact.provenance, f.artifact.provenance)
        let saved = try await journal.read()
        XCTAssertEqual(saved?.transfer, record)
        let states = await journal.states
        XCTAssertEqual(states, [.intent, .uploaded, .verified])
        XCTAssertFalse(record.requiresArtifactRetention)
    }

    func testInvalidArtifactAndFailedIntentPersistenceNeverStartUpload() async throws {
        let f = try ArtifactFixture(); defer { f.remove() }
        let transport = FakeReaderTransport()
        let journal = TransferJournal(root: f.root, failAt: .intent)
        do { _ = try await send(f, transport, journal); XCTFail("Intent failure must stop upload") } catch {}
        var objects = try await transport.list()
        XCTAssertTrue(objects.isEmpty)
        try Data("changed".utf8).write(to: f.artifact.localURL)
        let goodJournal = TransferJournal(root: f.root)
        do { _ = try await send(f, transport, goodJournal); XCTFail("Changed bytes must stop upload") } catch {}
        objects = try await transport.list()
        XCTAssertTrue(objects.isEmpty)
        let states = await goodJournal.states
        XCTAssertTrue(states.isEmpty)
    }

    func testDisconnectBeforeHandleReturnRetainsUnknownOutcomeWithoutRetry() async throws {
        let f = try ArtifactFixture(); defer { f.remove() }
        let transport = FakeReaderTransport(fault: .disconnectAfterWrite)
        let journal = TransferJournal(root: f.root)
        do { _ = try await send(f, transport, journal); XCTFail("Disconnect must not report success") } catch {}
        let saved = try await journal.read()
        let record = try XCTUnwrap(saved?.transfer)
        XCTAssertEqual(record.state, .needsReview)
        XCTAssertNil(record.itemID)
        XCTAssertTrue(record.requiresArtifactRetention)
        XCTAssertEqual(try f.artifact.verifiedData(), f.bytes)
        let objects = try await transport.list()
        XCTAssertEqual(objects.count, 1, "No automatic replay or cleanup of a possibly finished upload")
    }

    func testCorruptReadbackAndCancellationRetainReturnedIdentity() async throws {
        for fault in [FakeReaderTransport.Fault.corruptReadback, .cancelDuringFetch, .shortRead, .oversizedRead] {
            let f = try ArtifactFixture(); defer { f.remove() }
            let transport = FakeReaderTransport(fault: fault)
            let journal = TransferJournal(root: f.root)
            do { _ = try await send(f, transport, journal); XCTFail("Failed readback must not be verified") } catch {}
            let saved = try await journal.read()
            let record = try XCTUnwrap(saved?.transfer)
            XCTAssertEqual(record.state, .needsReview)
            XCTAssertNotNil(record.itemID)
            XCTAssertTrue(record.requiresArtifactRetention)
        }
    }

    func testReusedHandleAfterReconnectCannotVerifyOldUpload() async throws {
        let f = try ArtifactFixture(); defer { f.remove() }
        let transport = FakeReaderTransport(fault: .reconnectAfterUpload)
        let journal = TransferJournal(root: f.root)
        do { _ = try await send(f, transport, journal); XCTFail("Reconnection invalidates the selection") } catch {}
        let saved = try await journal.read()
        let record = try XCTUnwrap(saved?.transfer)
        XCTAssertEqual(record.state, .needsReview)
        let current = await transport.destination
        XCTAssertNotEqual(record.destination, current)
        XCTAssertThrowsError(try record.itemID?.requireCurrent(current))
    }

    func testLegacyReceiptDecodesAndFutureTransferVersionIsRejected() async throws {
        let legacy = Data(#"{"id":"11111111-1111-1111-1111-111111111111","operation":"send","source":"/reader","sourceHash":"old-hash","backup":"file:///tmp/book.mobi","date":0,"state":"needsReview"}"#.utf8)
        let receipt = try JSONDecoder().decode(ReaderReceipt.self, from: legacy)
        XCTAssertNil(receipt.transfer)
        XCTAssertEqual(receipt.state, "needsReview")
        let f = try ArtifactFixture(); defer { f.remove() }
        let record = ReaderTransferRecord(artifact: f.artifact, destination: FakeReaderTransport.makeDestination())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json["schemaVersion"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(ReaderTransferRecord.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    func testReceiptFailuresAfterUploadPreserveReviewAndNeverReplay() async throws {
        for state in [ReaderTransferRecord.State.uploaded, .verified, .needsReview] {
            let f = try ArtifactFixture(); defer { f.remove() }
            let transport = FakeReaderTransport(fault: state == .needsReview ? .disconnectAfterWrite : .none)
            let journal = TransferJournal(root: f.root, failAt: state)
            do { _ = try await send(f, transport, journal); XCTFail("Receipt failure cannot report completion") }
            catch let error as ReaderArtifactTransferFailure {
                XCTAssertEqual(error.record.state, .needsReview)
                XCTAssertEqual(error.receiptUpdateFailed, state == .needsReview)
            }
            let saved = try await journal.read()
            let record = try XCTUnwrap(saved?.transfer)
            XCTAssertEqual(record.state, state == .needsReview ? .intent : .needsReview)
            XCTAssertTrue(record.requiresArtifactRetention)
            let objects = try await transport.list()
            XCTAssertEqual(objects.count, 1)
        }
    }

    func testUploadUsesSnapshotWhenArtifactChangesAfterIntent() async throws {
        let f = try ArtifactFixture(); defer { f.remove() }
        let transport = FakeReaderTransport()
        let journal = TransferJournal(root: f.root)
        let record = try await ReaderArtifactTransfer.send(f.artifact, to: transport.destination, using: transport,
                                                          readbackDirectory: f.root, persist: { record in
            try await journal.save(record)
            if record.state == .intent { try Data("later edit".utf8).write(to: f.artifact.localURL) }
        })
        XCTAssertEqual(record.state, .verified)
        XCTAssertEqual(record.artifact.outputSHA256, SHA256Digest.digest(f.bytes))
        XCTAssertThrowsError(try record.artifact.verifiedData(), "Future use must explicitly fail instead of silently regenerating")
    }

    func testUnverifiedInventoryAndInvalidIdentitiesCannotEstablishMatch() async throws {
        let current = FakeReaderTransport.makeDestination()
        let item = ReaderItemID(destination: current, locator: .mtp(objectHandle: 1, parentObject: 7))
        try item.requireCurrent(current)
        for invalid in [
            ReaderItemID(destination: current, locator: .mtp(objectHandle: 0, parentObject: 7)),
            ReaderItemID(destination: current, locator: .mtp(objectHandle: 1, parentObject: 8)),
            ReaderItemID(destination: current, locator: .mounted(relativePath: "book.mobi"))
        ] { XCTAssertThrowsError(try invalid.requireCurrent(current)) }
        let mounted = ReaderDestination(connection: UUID(), endpoint: .mounted(root: URL(fileURLWithPath: "/tmp/reader"), rootIdentity: "fixture"))
        for path in ["../book.mobi", "/book.mobi", "folder//book.mobi", "folder/./book.mobi"] {
            XCTAssertThrowsError(try ReaderItemID(destination: mounted, locator: .mounted(relativePath: path)).requireCurrent(mounted))
        }
        let json = Data(#"{"unverified":{}}"#.utf8)
        let hash = try JSONDecoder().decode(ReaderContentHash.self, from: json)
        XCTAssertEqual(hash, .unverified)
        XCTAssertNotEqual(hash, .verified(SHA256Digest.digest(Data())))
    }

    func testActuallyCancelledTaskStillPersistsReviewReceipt() async throws {
        let f = try ArtifactFixture(); defer { f.remove() }
        let started = expectation(description: "Fetch started")
        let transport = FakeReaderTransport(fault: .waitForCancellation, onFetch: { started.fulfill() })
        let journal = TransferJournal(root: f.root)
        let operation = Task { try await self.send(f, transport, journal) }
        await fulfillment(of: [started], timeout: 3)
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled transfer must need review") }
        catch let failure as ReaderArtifactTransferFailure {
            XCTAssertEqual(failure.record.state, .needsReview)
            XCTAssertFalse(failure.receiptUpdateFailed)
        }
        let saved = try await journal.read()
        XCTAssertEqual(saved?.transfer?.state, .needsReview)
        let persistedWhileCancelled = await journal.persistedWhileCancelled
        XCTAssertTrue(persistedWhileCancelled)
    }

    private func send(_ f: ArtifactFixture, _ transport: FakeReaderTransport, _ journal: TransferJournal) async throws -> ReaderTransferRecord {
        try await ReaderArtifactTransfer.send(f.artifact, to: transport.destination, using: transport,
                                             readbackDirectory: f.root, persist: { try await journal.save($0) })
    }
}

/// Replaces only external device I/O; coordinator validation and on-disk receipt writes stay real.
actor FakeReaderTransport: ReaderTransport {
    enum Fault { case none, disconnectAfterWrite, corruptReadback, cancelDuringFetch, reconnectAfterUpload, shortRead, oversizedRead, waitForCancellation }
    var destination = makeDestination()
    let capabilities: ReaderCapabilities = [.list, .fetch, .uploadNew]
    private let fault: Fault
    private let onFetch: @Sendable () -> Void
    private var objects: [ReaderItemID: Data] = [:]
    init(fault: Fault = .none, onFetch: @escaping @Sendable () -> Void = {}) { self.fault = fault; self.onFetch = onFetch }
    static func makeDestination() -> ReaderDestination {
        ReaderDestination(connection: UUID(), endpoint: .mtp(deviceIdentity: "authored-device", storageID: 1, parentObject: 7))
    }
    func list() async throws -> [ReaderTransportItem] {
        objects.map { ReaderTransportItem(id: $0.key, name: "book.mobi", byteCount: $0.value.count, contentHash: .unverified) }
    }
    func uploadNew(_ bytes: Data, suggestedFilename: String, to selected: ReaderDestination) async throws -> ReaderItemID {
        guard selected == destination else { throw ReaderTransportError.staleSelection }
        let item = ReaderItemID(destination: destination, locator: .mtp(objectHandle: UInt32(objects.count + 1), parentObject: 7))
        objects[item] = bytes
        if fault == .disconnectAfterWrite { throw ReaderTransportError.outcomeUnknown }
        if fault == .reconnectAfterUpload { destination = Self.makeDestination() }
        return item
    }
    func fetch(_ item: ReaderItemID, to localURL: URL, maximumBytes: Int) async throws {
        try item.requireCurrent(destination)
        guard var bytes = objects[item] else { throw ReaderTransportError.staleSelection }
        onFetch()
        if fault == .waitForCancellation { try await Task.sleep(for: .seconds(30)) }
        if fault == .cancelDuringFetch { throw CancellationError() }
        if fault == .corruptReadback { bytes[0] ^= 1 }
        if fault == .shortRead { bytes.removeLast() }
        if fault == .oversizedRead { bytes.append(0) }
        // Deliberately violate the adapter's declared limit for oversizedRead to exercise the consumer's check.
        try bytes.write(to: localURL, options: .withoutOverwriting)
    }
}

actor TransferJournal {
    let root: URL
    let failAt: ReaderTransferRecord.State?
    var states: [ReaderTransferRecord.State] = []
    var persistedWhileCancelled = false
    init(root: URL, failAt: ReaderTransferRecord.State? = nil) { self.root = root; self.failAt = failAt }
    func save(_ record: ReaderTransferRecord) throws {
        if record.state == failAt { throw CocoaError(.fileWriteOutOfSpace) }
        let receipt = ReaderReceipt(id: record.id, operation: "send", source: "fixture", sourceHash: record.artifact.outputSHA256.value,
                                    backup: root.appendingPathComponent("book.mobi"), date: Date(), state: record.state.rawValue, transfer: record)
        try receipt.save()
        if Task.isCancelled { persistedWhileCancelled = true }
        states.append(record.state)
    }
    func read() throws -> ReaderReceipt? {
        let file = root.appendingPathComponent("receipt.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(ReaderReceipt.self, from: Data(contentsOf: file))
    }
}
