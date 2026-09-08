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
