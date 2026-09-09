import XCTest
import AppKit
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class ReaderLifecycleTests: XCTestCase {
    func testUnrelatedMountDoesNotDiscardChosenReader() {
        let reader = ReaderModel()
        reader.libraryReady = true
        reader.folder = URL(fileURLWithPath: "/tmp/chosen-reader")
        reader.rootIdentity = "verified"
        let generation = reader.generation
        reader.mounted(URL(fileURLWithPath: "/Volumes/Installer"))
        XCTAssertEqual(reader.folder?.path, "/tmp/chosen-reader")
        XCTAssertEqual(reader.rootIdentity, "verified")
        XCTAssertEqual(reader.generation, generation)
        XCTAssertFalse(reader.busy)
    }

    func testSleepInvalidatesSelectionAndWakeDoesNotRestartWork() async throws {
        let reader = ReaderModel()
        reader.libraryReady = true
        reader.localRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        reader.folder = URL(fileURLWithPath: "/tmp/chosen-reader")
        reader.rootIdentity = "verified"
        let generation = reader.generation
        let operation = Task { try await Task.sleep(for: .seconds(30)) }
        reader.task = Task { _ = try? await operation.value }
        let readerTask = reader.task
        reader.busy = true
        reader.systemWillSleep()
        XCTAssertTrue(readerTask!.isCancelled)
        XCTAssertNil(reader.rootIdentity)
        XCTAssertNotEqual(reader.generation, generation)
        reader.refresh()
        reader.discover()
        reader.connect(URL(fileURLWithPath: "/tmp/other"))
        XCTAssertFalse(reader.busy)
        XCTAssertEqual(reader.folder?.path, "/tmp/chosen-reader")
        reader.systemDidWake()
        XCTAssertFalse(reader.busy)
        XCTAssertNil(reader.task)
        XCTAssertNil(reader.rootIdentity)
        XCTAssertTrue(reader.status?.contains("Writes may have finished") == true)
        operation.cancel()
    }
}

extension ReaderLifecycleTests {
    func testWorkspaceSleepNotificationsWorkWithoutAView() async {
        let center = NotificationCenter()
        let reader = ReaderModel(notificationCenter: center)
        reader.libraryReady = true
        reader.folder = URL(fileURLWithPath: "/tmp/reader")
        reader.rootIdentity = "verified"
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Drain the main queue used by the workspace subscriptions.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertNil(reader.rootIdentity)
        reader.refresh()
        XCTAssertFalse(reader.busy)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertFalse(reader.busy)
        XCTAssertTrue(reader.status?.contains("Refresh") == true)
    }

    func testKindleMountStartsDiscoveryButSimilarVolumeNameDoesNot() {
        let reader = ReaderModel()
        reader.libraryReady = true
        reader.localRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        reader.mounted(URL(fileURLWithPath: "/Volumes/KindleBackup"))
        XCTAssertNil(reader.folder)
        XCTAssertFalse(reader.busy)
        reader.mounted(URL(fileURLWithPath: "/Volumes/Kindle"))
        XCTAssertEqual(reader.folder?.path, "/Volumes/Kindle/documents")
        XCTAssertTrue(reader.busy)
        // Cancel before the main-actor task launches; never access a real device.
        reader.systemWillSleep()
    }

    func testStartupDiscoversAlreadyMountedKindleOnly() {
        let reader = ReaderModel()
        reader.libraryReady = true
        reader.localRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        reader.discoverMounted(volumes: [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Volumes/KindleBackup")])
        XCTAssertNil(reader.folder)
        XCTAssertFalse(reader.busy)
        reader.discoverMounted(volumes: [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Volumes/Kindle")])
        XCTAssertEqual(reader.folder?.path, "/Volumes/Kindle/documents")
        XCTAssertTrue(reader.busy)
        reader.systemWillSleep()
    }

    func testStartupDiscoveryWaitsForLibraryAndKeepsChosenFolder() {
        let reader = ReaderModel()
        reader.discoverMounted(volumes: [URL(fileURLWithPath: "/Volumes/Kindle")])
        XCTAssertNil(reader.folder)
        reader.libraryReady = true
        reader.folder = URL(fileURLWithPath: "/tmp/chosen-reader")
        reader.discoverMounted(volumes: [URL(fileURLWithPath: "/Volumes/Kindle")])
        XCTAssertEqual(reader.folder?.path, "/tmp/chosen-reader")
        XCTAssertFalse(reader.busy)
    }
}

extension ReaderLifecycleTests {
    func testSendIsBlockedAfterSleepAndCancellationBeforeLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        let destination = root.appendingPathComponent("untouched-reader")
        model.reader.folder = destination
        model.reader.systemWillSleep()
        model.reader.systemDidWake()
        model.reader.send(book, destination: destination, model: model)
        XCTAssertFalse(model.reader.busy)
        XCTAssertTrue(model.error?.contains("after sleep") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        let fresh = AppModel(rootOverride: root)
        fresh.reader.send(book, destination: destination, model: fresh)
        XCTAssertTrue(fresh.reader.busy)
        fresh.reader.cancel()
        await Task.yield()
        XCTAssertFalse(fresh.reader.busy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
