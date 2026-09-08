import Foundation
import Darwin

/// Versioned transfer metadata embedded optionally in existing ReaderReceipt JSON. Retain the
/// artifact while an intent/upload/review receipt references it. A receipt is evidence, not mutation authority.
public struct ReaderTransferRecord: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case intent, uploaded, verified, needsReview }
    public let schemaVersion: Int
    public let id: UUID
    public let artifact: PreparedBookArtifact
    public let destination: ReaderDestination
    public private(set) var itemID: ReaderItemID?
    public private(set) var state: State
    public private(set) var detail: String?
    public var requiresArtifactRetention: Bool { state != .verified }

    public init(artifact: PreparedBookArtifact, destination: ReaderDestination) {
        schemaVersion = 1; id = UUID(); self.artifact = artifact; self.destination = destination
        state = .intent
    }
    mutating func uploaded(_ item: ReaderItemID) throws {
        // Preserve even an invalid returned identity for review, but never use it to fetch.
        itemID = item
        try item.requireCurrent(destination)
        state = .uploaded
    }
    mutating func verified() { state = .verified; detail = nil }
    mutating func needsReview(_ error: any Error) { state = .needsReview; detail = error.localizedDescription }

    private enum CodingKeys: String, CodingKey { case schemaVersion, id, artifact, destination, itemID, state, detail }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw BookError.unsupported("Unsupported transfer receipt version.") }
        id = try c.decode(UUID.self, forKey: .id)
        artifact = try c.decode(PreparedBookArtifact.self, forKey: .artifact)
        destination = try c.decode(ReaderDestination.self, forKey: .destination)
        itemID = try c.decodeIfPresent(ReaderItemID.self, forKey: .itemID)
        state = try c.decode(State.self, forKey: .state)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        if state == .uploaded || state == .verified {
            guard let itemID else { throw ReaderTransportError.invalidResponse }
            try itemID.requireCurrent(destination)
        }
        if state == .intent, itemID != nil { throw ReaderTransportError.invalidResponse }
    }
}

public struct ReaderArtifactTransferFailure: Error, LocalizedError, Sendable {
    public let record: ReaderTransferRecord
    /// If true, the last durable record may still be intent/uploaded. Neither permits automatic replay.
    public let receiptUpdateFailed: Bool
    public var errorDescription: String? {
        (record.detail ?? "Reader transfer needs review.") +
        (receiptUpdateFailed ? " The receipt update also failed; preserve the artifact and review before retrying." : " Review operation history before retrying.")
    }
}

/// Helper-side orchestration shared by future adapters. The persist callback must durably save each
/// record before returning; failure to save intent prevents upload. Callers must not automatically retry
/// errors. Existing mounted send paths are not switched to this coordinator in the contract increment.
public enum ReaderArtifactTransfer {
    public static func send(_ artifact: PreparedBookArtifact, to destination: ReaderDestination,
                            using transport: any ReaderTransport, readbackDirectory: URL,
                            persist: @Sendable (ReaderTransferRecord) async throws -> Void,
                            progress: @Sendable (ReaderTransferPhase) -> Void = { _ in }) async throws -> ReaderTransferRecord {
        progress(.preparing)
        try Task.checkCancellation()
        guard await transport.destination == destination else { throw ReaderTransportError.staleSelection }
        guard await transport.capabilities.isSuperset(of: [.uploadNew, .fetch]) else { throw ReaderTransportError.unsupported }
        let bytes = try artifact.verifiedData()
        guard readbackDirectory.isFileURL else { throw BookError.invalid("Readback must use local storage.") }
        let stage = readbackDirectory.appendingPathComponent("smallibre-readback-" + UUID().uuidString, isDirectory: true)
        guard mkdir(stage.path, 0o700) == 0 else { throw BookError.invalid("Could not create private readback storage.") }
        defer { try? FileManager.default.removeItem(at: stage) }
        let readback = stage.appendingPathComponent("book")
        var record = ReaderTransferRecord(artifact: artifact, destination: destination)
        try Task.checkCancellation()
        try await persist(record)
        do {
            try Task.checkCancellation()
            guard await transport.destination == destination else { throw ReaderTransportError.staleSelection }
            progress(.uploading)
            let item = try await transport.uploadNew(bytes, suggestedFilename: artifact.suggestedFilename, to: destination)
            try record.uploaded(item)
            try await persist(record)
            try Task.checkCancellation()
            try item.requireCurrent(await transport.destination)
            progress(.verifying)
            try await transport.fetch(item, to: readback, maximumBytes: artifact.byteCount)
            _ = try PreparedBookArtifact.readVerified(readback, byteCount: artifact.byteCount, sha256: artifact.outputSHA256)
            try item.requireCurrent(await transport.destination)
            try Task.checkCancellation()
            record.verified()
            try await persist(record)
            progress(.completed)
            return record
        } catch {
            record.needsReview(error)
            var receiptUpdateFailed = false
            do { try await persist(record) } catch { receiptUpdateFailed = true }
            throw ReaderArtifactTransferFailure(record: record, receiptUpdateFailed: receiptUpdateFailed)
        }
    }
}
