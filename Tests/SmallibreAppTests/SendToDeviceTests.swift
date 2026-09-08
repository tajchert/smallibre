import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class SendToDeviceTests: XCTestCase {
    func testConvertsAndSendsToSelectedDeviceWithoutOpeningSheet() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root.appendingPathComponent("library"))
        model.reader.helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let folder = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        model.reader.folder = folder
        try Data("existing book".utf8).write(to: folder.appendingPathComponent("A previous book.pdf"))
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        model.reader.sendToDevice(book, model: model)
        await model.reader.task?.value
        XCTAssertNil(model.error)
        XCTAssertNil(model.transferBook)
        XCTAssertTrue(model.status?.contains("Sent and verified") == true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "azw3" }.count, 1)
        XCTAssertFalse(files.contains { $0.pathExtension == "epub" })
        XCTAssertEqual(model.reader.receipts.filter { $0.transfer?.state == .verified }.count, 1)
        XCTAssertEqual(model.reader.deviceMatch(book), .converted)
        XCTAssertEqual(model.reader.books.count, 2)
        XCTAssertEqual(model.reader.books.first?.formatLabel, "AZW3")
        model.reader.refresh()
        await model.reader.task?.value
        XCTAssertEqual(model.reader.books.first?.formatLabel, "AZW3")
        model.reader.books = []
        model.reader.sendToDevice(book, model: model)
        await model.reader.task?.value
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "azw3" }.count, 1)

    }

    func testManualFolderSendUpdatesInventoryAndOriginalMatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root.appendingPathComponent("library"))
        model.reader.helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let folder = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        model.reader.send(book, destination: folder, model: model)
        await model.reader.task?.value
        XCTAssertNil(model.reader.error)
        XCTAssertEqual(model.reader.folder, folder)
        XCTAssertNotNil(model.reader.rootIdentity)
        XCTAssertEqual(model.reader.deviceMatch(book), .original)
        XCTAssertEqual(model.reader.books.count, 1)
    }

    func testRefreshAfterManualSendFailureTargetsNewDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root.appendingPathComponent("library"))
        let folder = root.appendingPathComponent("new-documents")
        model.reader.folder = root.appendingPathComponent("previous-documents")
        model.reader.rootIdentity = "previous-device"
        let helper = root.appendingPathComponent("helper")
        let response = String(decoding: try JSONEncoder().encode(ReaderResponse(file: folder.appendingPathComponent("book.epub"))), as: UTF8.self)
        // Simulate a verified send followed by an unavailable inventory scan.
        let script = """
        #!/bin/sh
        request=$(cat "$1")
        case "$request" in
          *scan*) printf '%s' '{"error":"Device unavailable during scan"}' ;;
          *) printf '%s' '\(response)' ;;
        esac
        """
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        model.reader.helper = helper
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        model.reader.send(book, destination: folder, model: model)
        await model.reader.task?.value
        XCTAssertTrue(model.status?.contains("Sent and verified") == true)
        XCTAssertTrue(model.reader.error?.contains("could not refresh") == true)
        XCTAssertEqual(model.reader.folder, folder)
        XCTAssertNil(model.reader.rootIdentity)
        XCTAssertFalse(model.reader.busy)
    }

    func testMissingDeviceFallsBackWithoutConvertingOrWriting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        model.reader.helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        model.reader.folder = root.appendingPathComponent("missing-device")
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        model.reader.sendToDevice(book, model: model)
        await model.reader.task?.value
        XCTAssertEqual(model.transferBook?.id, book.id)
        XCTAssertFalse(model.reader.busy)
        XCTAssertTrue(model.reader.receipts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing-device").path))
    }
}

extension SendToDeviceTests {
    func testCancellationAndSleepNeverStartAutomaticSend() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        model.reader.folder = root.appendingPathComponent("missing-device")
        model.reader.sendToDevice(book, model: model)
        let task = model.reader.task
        model.reader.cancel()
        await task?.value
        XCTAssertNil(model.transferBook)
        XCTAssertTrue(model.reader.receipts.isEmpty)
        model.reader.systemWillSleep()
        model.reader.systemDidWake()
        model.reader.sendToDevice(book, model: model)
        XCTAssertFalse(model.reader.busy)
        XCTAssertTrue(model.error?.contains("after sleep") == true)
        XCTAssertNil(model.transferBook)
    }

    func testChangedDeviceIdentityDoesNotSend() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root.appendingPathComponent("library"))
        model.reader.helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let folder = root.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        model.reader.folder = folder
        model.reader.rootIdentity = "previous-device"
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        model.reader.sendToDevice(book, model: model)
        await model.reader.task?.value
        XCTAssertEqual(model.transferBook?.id, book.id)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        XCTAssertTrue(model.reader.receipts.isEmpty)
    }
}
