import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class StartupTests: XCTestCase {
    func testDeviceActionsCannotCreateLibraryAfterFailedStartup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appendingPathComponent("device"), library = root.appendingPathComponent("uninitialized")
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        try FileManager.default.copyItem(at: fixture, to: device.appendingPathComponent("book.epub"))
        let scan = try await ReaderStore(root: device).scan()
        let model = AppModel(rootOverride: library, initialize: false)
        model.reader.connect(device)
        XCTAssertNil(model.reader.folder)
        model.reader.folder = device
        model.reader.run("download", books: scan, model: model)
        XCTAssertFalse(model.reader.busy)
        XCTAssertNil(model.store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.path))
    }
}
