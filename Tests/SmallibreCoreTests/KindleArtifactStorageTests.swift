import XCTest
@testable import SmallibreCore

final class KindleArtifactStorageTests: XCTestCase, @unchecked Sendable {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testPreparationCachesVerifiedArtifactAndPreservesOriginal() async throws {
        let root = try directory(), store = try LibraryStore(root: root)
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let original = try Data(contentsOf: source)
        let book = try await store.importBook(from: source).book
        let first = try await store.prepareKindleArtifact(for: book.id)
        let second = try await store.prepareKindleArtifact(for: book.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.provenance.sourceOriginalSHA256, .digest(original))
        XCTAssertEqual(first.provenance.preparedInputSHA256, .digest(original))
        XCTAssertEqual(first.provenance.sourceLibraryID, book.id)
        XCTAssertEqual(first.outputFormat, .azw3)
        let originalURL = try await store.originalURL(for: book.id)
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        let reopened = try LibraryStore(root: root)
        let cached = try await reopened.prepareKindleArtifact(for: book.id)
        XCTAssertEqual(cached.id, first.id)
        let exportFolder = try directory()
        let a = try await store.exportKindleArtifact(first, to: exportFolder)
        let b = try await store.exportKindleArtifact(first, to: exportFolder)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try Data(contentsOf: a), try first.verifiedData())
    }
    func testMetadataChangeProducesNewArtifactAndRetainsOldBytes() async throws {
        let store = try LibraryStore(root: directory())
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        var book = try await store.importBook(from: source).book
        let first = try await store.prepareKindleArtifact(for: book.id)
        let bytes = try first.verifiedData()
        book.metadata.title = "A revised title"
        try await store.update(book)
        let second = try await store.prepareKindleArtifact(for: book.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.provenance.settingsSHA256, second.provenance.settingsSHA256)
        XCTAssertNotEqual(first.provenance.preparedInputSHA256, second.provenance.preparedInputSHA256)
        XCTAssertEqual(try first.verifiedData(), bytes)
    }
    func testPreparationWithTemporaryDirectoryAlias() async throws {
        let root = URL(fileURLWithPath: "/tmp/smallibre-alias-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        let source = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        let book = try await store.importBook(from: source).book
        let artifact = try await store.prepareKindleArtifact(for: book.id)
        try artifact.requireStored(in: root)
    }
    func testSampleWithSavedTypographyPreparesForKindle() async throws {
        let store = try LibraryStore(root: directory())
        let source = Bundle.module.url(forResource: "Small Hours", withExtension: "epub", subdirectory: "Fixtures")!
        var book = try await store.importBook(from: source).book
        book.metadata.title = "Workflow test"
        book.typography = TypographySettings(enabled: true, font: .serif, lineHeight: 1.8, marginPercent: 5)
        try await store.update(book)
        let artifact = try await store.prepareKindleArtifact(for: book.id)
        XCTAssertEqual(try MOBIBook.inspect(artifact.verifiedData()).title, "Workflow test")
    }
    func testChangedManifestAndSymlinkStorageAreRejected() async throws {
        let root = try directory(), store = try LibraryStore(root: root)
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let book = try await store.importBook(from: source).book
        let artifact = try await store.prepareKindleArtifact(for: book.id)
        let folder = artifact.localURL.deletingLastPathComponent()
        let manifest = folder.appendingPathComponent("artifact.json")
        let saved = try Data(contentsOf: manifest)
        try Data("{}".utf8).write(to: manifest)
        XCTAssertThrowsError(try artifact.requireStored(in: root))
        try saved.write(to: manifest)
        let moved = root.appendingPathComponent("moved-conversion")
        try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: moved)
        XCTAssertThrowsError(try artifact.requireStored(in: root))
    }
    func testCancellationDoesNotPublishAndNonEPUBIsRejected() async throws {
        let root = try directory(), store = try LibraryStore(root: root)
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let book = try await store.importBook(from: source).book
        let task = Task { try Task.checkCancellation(); return try await store.prepareKindleArtifact(for: book.id) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled conversion must fail") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let mobi = Bundle.module.url(forResource: "minimal", withExtension: "mobi", subdirectory: "Fixtures")!
        let other = try await store.importBook(from: mobi).book
        do { _ = try await store.prepareKindleArtifact(for: other.id); XCTFail("MOBI must not be converted as EPUB") } catch {}
    }
    func testCorruptCachedOutputIsNotSilentlyReplacedOrExported() async throws {
        let store = try LibraryStore(root: directory())
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let book = try await store.importBook(from: source).book
        let artifact = try await store.prepareKindleArtifact(for: book.id)
        try Data("corrupt".utf8).write(to: artifact.localURL)
        do { _ = try await store.prepareKindleArtifact(for: book.id); XCTFail("Corrupt cached bytes must fail") } catch {}
        do { _ = try await store.exportKindleArtifact(artifact, to: directory()); XCTFail("Corrupt output must not export") } catch {}
        XCTAssertEqual(try Data(contentsOf: artifact.localURL), Data("corrupt".utf8))
    }
}
