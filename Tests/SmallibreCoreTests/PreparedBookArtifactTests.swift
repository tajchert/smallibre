import XCTest
@testable import SmallibreCore

final class PreparedBookArtifactTests: XCTestCase {
    func testCapturedBytesSurviveManifestRoundTripAndKeepSourceSeparate() throws {
        let fixture = try ArtifactFixture()
        defer { fixture.remove() }
        let decoded = try JSONDecoder().decode(PreparedBookArtifact.self, from: JSONEncoder().encode(fixture.artifact))
        XCTAssertEqual(try decoded.verifiedData(), fixture.bytes)
        XCTAssertEqual(decoded.provenance.sourceOriginalSHA256.value, String(repeating: "a", count: 64))
        XCTAssertNotEqual(decoded.provenance.sourceOriginalSHA256, decoded.outputSHA256)
        XCTAssertEqual(decoded.provenance.converterVersion, "fixture-1")
    }

    func testChangedMissingAndSymlinkArtifactsCannotBeUsed() throws {
        let fixture = try ArtifactFixture()
        defer { fixture.remove() }
        var changed = fixture.bytes
        changed[0] ^= 1
        try changed.write(to: fixture.artifact.localURL)
        XCTAssertThrowsError(try fixture.artifact.verifiedData())
        try FileManager.default.removeItem(at: fixture.artifact.localURL)
        XCTAssertThrowsError(try fixture.artifact.verifiedData())
        let replacement = fixture.root.appendingPathComponent("replacement")
        try fixture.bytes.write(to: replacement)
        try FileManager.default.createSymbolicLink(at: fixture.artifact.localURL, withDestinationURL: replacement)
        XCTAssertThrowsError(try fixture.artifact.verifiedData())
    }

    func testUntrustedManifestCannotBypassValidation() throws {
        let fixture = try ArtifactFixture()
        defer { fixture.remove() }
        let data = try JSONEncoder().encode(fixture.artifact)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (field, value) in [("schemaVersion", 99), ("byteCount", -1), ("byteCount", 268435457),
                               ("suggestedFilename", "../book.mobi"), ("suggestedFilename", "book.azw3"),
                               ("suggestedFilename", "book\u{0}.mobi"), ("localURL", "https://example.com/book.mobi"),
                               ("outputSHA256", "bad")] as [(String, Any)] {
            var json = original; json[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(PreparedBookArtifact.self, from: JSONSerialization.data(withJSONObject: json)), field)
        }
    }

    func testCacheIdentityIncludesPreparedBytesSettingsProfileAndVersion() throws {
        let hash = try SHA256Digest(String(repeating: "a", count: 64))
        let other = try SHA256Digest(String(repeating: "b", count: 64))
        let key = PreparedBookProvenance(sourceLibraryID: UUID(), sourceOriginalSHA256: hash, preparedInputSHA256: hash,
                                         settingsSHA256: hash, converterVersion: "1", profile: "kf8-prose")
        for changed in [
            PreparedBookProvenance(sourceLibraryID: key.sourceLibraryID, sourceOriginalSHA256: hash, preparedInputSHA256: other, settingsSHA256: hash, converterVersion: "1", profile: "kf8-prose"),
            PreparedBookProvenance(sourceLibraryID: key.sourceLibraryID, sourceOriginalSHA256: hash, preparedInputSHA256: hash, settingsSHA256: other, converterVersion: "1", profile: "kf8-prose"),
            PreparedBookProvenance(sourceLibraryID: key.sourceLibraryID, sourceOriginalSHA256: hash, preparedInputSHA256: hash, settingsSHA256: hash, converterVersion: "2", profile: "kf8-prose"),
            PreparedBookProvenance(sourceLibraryID: key.sourceLibraryID, sourceOriginalSHA256: hash, preparedInputSHA256: hash, settingsSHA256: hash, converterVersion: "1", profile: "kf8-other")
        ] { XCTAssertNotEqual(key, changed) }
    }
}

struct ArtifactFixture {
    let root: URL
    let bytes: Data
    let artifact: PreparedBookArtifact
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        bytes = try Data(contentsOf: Bundle.module.url(forResource: "minimal", withExtension: "mobi", subdirectory: "Fixtures")!)
        let file = root.appendingPathComponent("book.mobi")
        try bytes.write(to: file)
        let sourceHash = try SHA256Digest(String(repeating: "a", count: 64))
        artifact = try PreparedBookArtifact(id: UUID(), provenance: PreparedBookProvenance(
            sourceLibraryID: UUID(), sourceOriginalSHA256: sourceHash, preparedInputSHA256: sourceHash,
            settingsSHA256: sourceHash, converterVersion: "fixture-1", profile: "original-mobi"),
            outputFormat: .mobi, suggestedFilename: "book.mobi", localURL: file, byteCount: bytes.count,
            outputSHA256: SHA256Digest.digest(bytes), warnings: [])
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
