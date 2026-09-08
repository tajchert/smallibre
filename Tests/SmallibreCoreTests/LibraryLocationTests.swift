import XCTest
@testable import SmallibreCore

final class LibraryLocationTests: XCTestCase {
    func testMovesLegacyLibraryAndKeepsOldBackupPathsWorking() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let old = support.appendingPathComponent("Calibre Nova")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("preserved".utf8).write(to: old.appendingPathComponent("library.sqlite"))
        let result = try LibraryLocation.prepare(in: support)
        XCTAssertEqual(result.lastPathComponent, "Smallibre")
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("library.sqlite")), Data("preserved".utf8))
        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("library.sqlite")), Data("preserved".utf8))
        XCTAssertEqual(try LibraryLocation.prepare(in: support), result)
    }
    func testDoesNotMergeOrOverwriteTwoExistingLibraries() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        for name in ["Calibre Nova", "Smallibre"] { try FileManager.default.createDirectory(at: support.appendingPathComponent(name), withIntermediateDirectories: true) }
        let old = support.appendingPathComponent("Calibre Nova/keep")
        try Data("old".utf8).write(to: old)
        let result = try LibraryLocation.prepare(in: support)
        XCTAssertEqual(result.lastPathComponent, "Smallibre")
        XCTAssertEqual(try Data(contentsOf: old), Data("old".utf8))
    }
}

extension LibraryLocationTests {
    func testInterruptedMigrationRepairsBackupAliasOnRetry() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent(LibraryLocation.legacyDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("backup".utf8).write(to: legacy.appendingPathComponent("backup.mobi"))
        XCTAssertThrowsError(try LibraryLocation.prepare(in: support, afterMove: { throw CancellationError() }))
        let result = try LibraryLocation.prepare(in: support)
        XCTAssertEqual(result.lastPathComponent, "Smallibre")
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("backup.mobi")), Data("backup".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent(".smallibre-library-migration").path))
    }
}

extension LibraryLocationTests {
    func testPartialNewCacheDoesNotHideExistingLibrary() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent(LibraryLocation.legacyDirectory), target = support.appendingPathComponent("Smallibre")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("database".utf8).write(to: legacy.appendingPathComponent("library.sqlite"))
        try Data("cache".utf8).write(to: target.appendingPathComponent("reader-cache.json"))
        _ = try LibraryLocation.prepare(in: support)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("library.sqlite")), Data("database".utf8))
        let preserved = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("Smallibre-before-migration-") })
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("reader-cache.json")), Data("cache".utf8))
    }
}
