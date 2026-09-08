import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class ReaderStateRegressionTests: XCTestCase {
    func testDeviceOnlySelectionExposesAvailableDetailsWithoutLibraryMatch() {
        let model = AppModel(initialize: false)
        model.filter = "device"
        let metadata = BookMetadata(title: "Device-only novel", authors: ["Sample Author"], language: "en", identifier: "", publisher: "", description: "", format: "MOBI", cover: nil)
        let mobi = ReaderBook(connection: model.reader.generation, relativePath: "novel.mobi", metadata: metadata,
                              hash: "mobi-bytes", byteCount: 1234, issue: nil)
        let kfx = ReaderBook(connection: model.reader.generation, relativePath: "Unknown title.kfx", metadata: nil,
                             hash: "kfx-bytes", byteCount: 5678, issue: "KFX metadata is unavailable.")
        model.reader.books = [mobi, kfx]
        model.reader.selectedIDs = [mobi.id]
        XCTAssertNil(model.selected)
        XCTAssertEqual(model.selectedDeviceBook?.metadata?.authors, ["Sample Author"])
        XCTAssertEqual(model.selectedDeviceBook?.byteCount, 1234)
        model.reader.selectedIDs = [kfx.id]
        XCTAssertEqual(model.selectedDeviceBook?.title, "Unknown title")
        XCTAssertEqual(model.selectedDeviceBook?.formatLabel, "KFX")
        XCTAssertEqual(model.selectedDeviceBook?.issue, "KFX metadata is unavailable.")
        model.search = "no matching book"
        XCTAssertNil(model.selectedDeviceBook)
        model.search = ""
        model.reader.selectedIDs = [mobi.id, kfx.id]
        XCTAssertNil(model.selectedDeviceBook)
        model.reader.selectedIDs = [kfx.id]
        model.reader.books = []
        XCTAssertNil(model.selectedDeviceBook)
        model.reader.books = [mobi]; model.reader.selectedIDs = [mobi.id]
        model.filter = "all"
        XCTAssertNil(model.selectedDeviceBook)
    }

    func testExportOnlyRoutesToSelectedReaderFolder() {
        let model = AppModel(initialize: false)
        let external = URL(fileURLWithPath: "/Volumes/Backup/Exports")
        XCTAssertFalse(model.exportUsesReader(external))
        XCTAssertTrue(model.exportNeedsHelper(external))
        XCTAssertTrue(model.exportNeedsHelper(URL(fileURLWithPath: "/Volumes/Kindle/documents")))
        XCTAssertFalse(model.exportNeedsHelper(URL(fileURLWithPath: "/tmp/local-export")))
        model.reader.folder = URL(fileURLWithPath: "/Volumes/Kindle/documents")
        XCTAssertFalse(model.exportUsesReader(external))
        XCTAssertTrue(model.exportUsesReader(URL(fileURLWithPath: "/Volumes/Kindle/documents")))
        XCTAssertTrue(model.exportUsesReader(URL(fileURLWithPath: "/Volumes/Kindle/documents/Books")))
        XCTAssertFalse(model.exportUsesReader(URL(fileURLWithPath: "/Volumes/Kindle/documents-backup")))
        XCTAssertFalse(model.exportUsesReader(URL(fileURLWithPath: "/Volumes/Kindle/documents/../other")))
        model.reader.folder = URL(fileURLWithPath: "/tmp/reader")
        XCTAssertTrue(model.exportUsesReader(URL(fileURLWithPath: "/tmp/reader/Books")))
    }

    func testHelperExportDoesNotAdoptDestinationOrReplaceInventory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root.appendingPathComponent("library"))
        model.reader.helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/SmallibreReaderHelper")
        let destination = root.appendingPathComponent("export-folder")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        let selectedFolder = root.appendingPathComponent("selected-reader")
        model.reader.folder = selectedFolder; model.reader.rootIdentity = "selected-reader-identity"
        let generation = model.reader.generation
        let item = ReaderBook(connection: generation, relativePath: "existing.epub", metadata: book.metadata,
                              hash: book.hash, byteCount: book.byteCount, issue: nil)
        model.reader.books = [item]; model.reader.selectedIDs = [item.id]
        model.reader.send(book, destination: destination, model: model, updateInventory: false)
        await model.reader.task?.value
        XCTAssertNil(model.reader.error)
        XCTAssertEqual(model.reader.folder, selectedFolder)
        XCTAssertEqual(model.reader.rootIdentity, "selected-reader-identity")
        XCTAssertEqual(model.reader.generation, generation)
        XCTAssertEqual(model.reader.books.map(\.id), [item.id])
        XCTAssertEqual(model.reader.selectedIDs, [item.id])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).filter { $0.hasSuffix(".epub") }.count, 1)
    }

    func testUnmountInvalidatesVolumeRootAndDescendantsOnly() {
        for selected in ["/Volumes/Kindle", "/Volumes/Kindle/documents"] {
            let reader = ReaderModel()
            reader.localRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            reader.folder = URL(fileURLWithPath: selected)
            reader.rootIdentity = "connected"
            let generation = reader.generation
            reader.disconnected(URL(fileURLWithPath: "/Volumes/KindleBackup"))
            XCTAssertEqual(reader.generation, generation)
            reader.disconnected(URL(fileURLWithPath: "/Volumes/Kindle"))
            XCTAssertNil(reader.folder)
            XCTAssertNil(reader.rootIdentity)
            XCTAssertNotEqual(reader.generation, generation)
        }
    }

    func testDeviceInspectorTracksInventoryAndVisibleSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        await model.reload()
        model.selection = book.id
        model.filter = "device"
        let item = ReaderBook(connection: model.reader.generation, relativePath: "book.epub", metadata: book.metadata,
                              hash: book.hash, byteCount: book.byteCount, issue: nil)
        model.reader.books = [item]
        model.reader.selectedIDs = [item.id]
        XCTAssertEqual(model.selected?.id, book.id)
        model.search = "not a matching title"
        XCTAssertNil(model.selected)
        model.search = ""
        XCTAssertEqual(model.selected?.id, book.id)
        model.reader.books = [ReaderBook(connection: model.reader.generation, relativePath: item.id,
                                        metadata: book.metadata, hash: "changed-bytes", byteCount: 20, issue: nil)]
        XCTAssertNil(model.selected)
        model.reader.books = []
        XCTAssertNil(model.selected)
        XCTAssertTrue(model.reader.selectedIDs.isEmpty)
        model.reader.books = [item]
        XCTAssertNil(model.selected)
        model.reader.selectedIDs = [item.id]
        XCTAssertEqual(model.selected?.id, book.id)
        model.reader.generation = UUID()
        XCTAssertNil(model.selected)
        XCTAssertTrue(model.reader.selectedIDs.isEmpty)
        model.filter = "all"
        XCTAssertEqual(model.selected?.id, book.id)
    }

    func testExportSheetDisablesCommandsUntilDismissed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        await model.reload(); model.selection = book.id
        XCTAssertTrue(model.commandsAvailable)
        model.export(book)
        XCTAssertFalse(model.commandsAvailable)
        XCTAssertNil(model.commandSelection)
        model.exportBook = nil
        XCTAssertTrue(model.commandsAvailable)
        XCTAssertEqual(model.commandSelection?.id, book.id)
    }
}
