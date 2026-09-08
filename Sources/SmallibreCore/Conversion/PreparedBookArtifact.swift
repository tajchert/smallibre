import Foundation
import CryptoKit
import Darwin

/// A validated, lowercase SHA-256 value. Unknown hashes must use an optional or explicit enum case.
public struct SHA256Digest: Codable, Hashable, Sendable {
    public let value: String
    public init(_ value: String) throws {
        guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BookError.invalid("Invalid SHA-256 value.")
        }
        self.value = value
    }
    private init(bytes: SHA256.Digest) {
        value = bytes.map { String(format: "%02x", $0) }.joined()
    }
    public static func digest(_ data: Data) -> Self { Self(bytes: SHA256.hash(data: data)) }
    public init(from decoder: any Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(value)
    }
}

/// All inputs to preparation, captured before conversion; never consult mutable library state on retry.
/// This value plus output format is a cache identity. Do not persist Swift's randomized hashValue.
public struct PreparedBookProvenance: Codable, Hashable, Sendable {
    public let sourceLibraryID: UUID
    public let sourceOriginalSHA256: SHA256Digest
    public let preparedInputSHA256: SHA256Digest
    public let settingsSHA256: SHA256Digest
    public let converterVersion: String
    public let profile: String

    public init(sourceLibraryID: UUID, sourceOriginalSHA256: SHA256Digest, preparedInputSHA256: SHA256Digest,
                settingsSHA256: SHA256Digest, converterVersion: String, profile: String) {
        self.sourceLibraryID = sourceLibraryID; self.sourceOriginalSHA256 = sourceOriginalSHA256
        self.preparedInputSHA256 = preparedInputSHA256; self.settingsSHA256 = settingsSHA256
        self.converterVersion = converterVersion; self.profile = profile
    }
}

/// Immutable manifest describing validated output. The publisher must validate the book format before
/// constructing this manifest; verifiedData checks byte integrity, not Kindle readability.
/// Storage/retention is owned by conversion (C5). A URL alone does not make a file immutable.
public struct PreparedBookArtifact: Codable, Equatable, Sendable, Identifiable {
    public enum Format: String, Codable, Sendable { case epub, mobi, azw3 }
    public let schemaVersion: Int
    public let id: UUID
    public let provenance: PreparedBookProvenance
    public let outputFormat: Format
    public let suggestedFilename: String
    public let localURL: URL
    public let byteCount: Int
    public let outputSHA256: SHA256Digest
    public let warnings: [String]

    public init(id: UUID, provenance: PreparedBookProvenance, outputFormat: Format, suggestedFilename: String,
                localURL: URL, byteCount: Int, outputSHA256: SHA256Digest, warnings: [String]) throws {
        schemaVersion = 1; self.id = id; self.provenance = provenance; self.outputFormat = outputFormat
        self.suggestedFilename = suggestedFilename; self.localURL = localURL; self.byteCount = byteCount
        self.outputSHA256 = outputSHA256; self.warnings = warnings
        try validate()
    }

    private func validate() throws {
        guard schemaVersion == 1 else { throw BookError.unsupported("Unsupported prepared artifact version.") }
        guard localURL.isFileURL, localURL.host == nil || localURL.host == "" || localURL.host == "localhost",
              byteCount > 0, byteCount <= ZIPArchive.maximumSize,
              !provenance.converterVersion.isEmpty, !provenance.profile.isEmpty else {
            throw BookError.invalid("Invalid prepared artifact metadata.")
        }
        guard !suggestedFilename.hasPrefix("."), suggestedFilename.utf8.count <= 240,
              !suggestedFilename.contains("/"), !suggestedFilename.contains("\\"), !suggestedFilename.contains(":"),
              !suggestedFilename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (suggestedFilename as NSString).pathExtension == outputFormat.rawValue else {
            throw BookError.invalid("Invalid prepared artifact filename.")
        }
    }

    /// Read one bounded snapshot from an opened regular file. Reject a symlink leaf and never recreate
    /// missing bytes. Call off the main actor; consumers use the returned bytes, not a later URL reread.
    public func verifiedData() throws -> Data {
        try Self.readVerified(localURL, byteCount: byteCount, sha256: outputSHA256)
    }

    static func readVerified(_ url: URL, byteCount: Int, sha256: SHA256Digest) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL, byteCount > 0, byteCount <= ZIPArchive.maximumSize else {
            throw BookError.invalid("Invalid artifact size or location.")
        }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw BookError.invalid("Prepared file is missing or unavailable. Prepare it again explicitly.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size == byteCount else {
            throw BookError.invalid("Prepared file size or type changed.")
        }
        var bytes = Data()
        while bytes.count <= byteCount {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(1024 * 1024, byteCount - bytes.count + 1)) ?? Data()
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        guard bytes.count == byteCount, SHA256Digest.digest(bytes) == sha256 else {
            throw BookError.invalid("Prepared file failed byte verification.")
        }
        try Task.checkCancellation()
        return bytes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, provenance, outputFormat, suggestedFilename, localURL, byteCount, outputSHA256, warnings
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        provenance = try c.decode(PreparedBookProvenance.self, forKey: .provenance)
        outputFormat = try c.decode(Format.self, forKey: .outputFormat)
        suggestedFilename = try c.decode(String.self, forKey: .suggestedFilename)
        localURL = try c.decode(URL.self, forKey: .localURL)
        byteCount = try c.decode(Int.self, forKey: .byteCount)
        outputSHA256 = try c.decode(SHA256Digest.self, forKey: .outputSHA256)
        warnings = try c.decode([String].self, forKey: .warnings)
        try validate()
    }
}
