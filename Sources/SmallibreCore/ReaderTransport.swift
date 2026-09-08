import Foundation

/// An endpoint and one connection generation. A reconnect must create a new connection UUID,
/// even when USB identity, storage and object handles appear unchanged.
public struct ReaderDestination: Codable, Hashable, Sendable {
    public enum Endpoint: Codable, Hashable, Sendable {
        case mounted(root: URL, rootIdentity: String)
        case mtp(deviceIdentity: String?, storageID: UInt32, parentObject: UInt32)
    }
    public let connection: UUID
    public let endpoint: Endpoint
    public init(connection: UUID, endpoint: Endpoint) { self.connection = connection; self.endpoint = endpoint }
}

public struct ReaderItemID: Codable, Hashable, Sendable {
    public enum Locator: Codable, Hashable, Sendable {
        case mounted(relativePath: String)
        case mtp(objectHandle: UInt32, parentObject: UInt32)
    }
    public let destination: ReaderDestination
    public let locator: Locator
    public init(destination: ReaderDestination, locator: Locator) { self.destination = destination; self.locator = locator }

    /// Context validation only. Adapters must freshly resolve and verify content before acting;
    /// equality is never authority for deletion or proof of a byte match.
    public func requireCurrent(_ current: ReaderDestination) throws {
        guard destination == current else { throw ReaderTransportError.staleSelection }
        switch (destination.endpoint, locator) {
        case let (.mounted(root, identity), .mounted(path)):
            guard root.isFileURL, !identity.isEmpty, !path.isEmpty, !path.hasPrefix("/"),
                  !path.contains("\0"), !path.contains("\\"),
                  path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw ReaderTransportError.invalidResponse
            }
        case let (.mtp(_, _, parent), .mtp(handle, itemParent)):
            guard handle != 0, handle != UInt32.max, parent == itemParent else { throw ReaderTransportError.invalidResponse }
        default: throw ReaderTransportError.invalidResponse
        }
    }
}

public enum ReaderContentHash: Codable, Equatable, Sendable {
    case unverified
    case verified(SHA256Digest)
}

public struct ReaderTransportItem: Codable, Sendable, Identifiable {
    public let id: ReaderItemID
    public let name: String
    /// Nil means the adapter does not know the size. Names and sizes never establish a byte match.
    public let byteCount: Int?
    public let contentHash: ReaderContentHash
    public init(id: ReaderItemID, name: String, byteCount: Int?, contentHash: ReaderContentHash) {
        self.id = id; self.name = name; self.byteCount = byteCount; self.contentHash = contentHash
    }
}

public struct ReaderCapabilities: OptionSet, Codable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let list = Self(rawValue: 1 << 0)
    public static let fetch = Self(rawValue: 1 << 1)
    public static let uploadNew = Self(rawValue: 1 << 2)
    // Destructive capabilities and methods are intentionally reserved for M6's safety review.
}

public enum ReaderTransportError: Error, LocalizedError, Sendable {
    case staleSelection, unsupported, busy, disconnected, outcomeUnknown, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .staleSelection: "The reader connection or selected object changed. Refresh and select it again."
        case .unsupported: "The reader does not support this operation."
        case .busy: "The previous reader operation is still running or stopping."
        case .disconnected: "The reader disconnected."
        case .outcomeUnknown: "The write may have finished. Review operation history before retrying."
        case .invalidResponse: "The reader returned an invalid object identity or response."
        }
    }
}

public enum ReaderTransferPhase: String, Codable, Sendable { case preparing, uploading, verifying, completed }

/// Implementations run inside the reader helper and serialize device I/O. This contract does not
/// supply a USB backend, mounted adapter or helper session manager. No mutation may be replayed
/// automatically after timeout/cancellation. Device-provided checksums alone are not verification.
public protocol ReaderTransport: Sendable {
    var destination: ReaderDestination { get async }
    var capabilities: ReaderCapabilities { get async }
    func list() async throws -> [ReaderTransportItem]
    /// Resolve on the same connection; stream to a NEW local file with bounded bytes and no overwrite.
    func fetch(_ item: ReaderItemID, to localURL: URL, maximumBytes: Int) async throws
    /// Consume these captured bytes without re-preparing or rereading library state. Create a NEW
    /// object, choose/recheck a collision-safe name, and return its identity as soon as available.
    /// On ambiguous failure throw; do not delete a candidate or retry. Never overwrite an object.
    func uploadNew(_ bytes: Data, suggestedFilename: String, to destination: ReaderDestination) async throws -> ReaderItemID
}
