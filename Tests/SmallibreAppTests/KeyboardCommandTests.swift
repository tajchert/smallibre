import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class KeyboardCommandTests: XCTestCase {
    func testGlobalSearchLeavesDeviceAndFormatFiltersWhileKeepingQuery() {
        let model = AppModel(initialize: false)
        for filter in ["device", "prepared", "EPUB"] {
            model.filter = filter
            model.search = "Small Hours"
            model.prepareSearch(global: true)
            XCTAssertEqual(model.filter, "all")
            XCTAssertEqual(model.search, "Small Hours")
        }
        model.filter = "device"
        model.prepareSearch(global: false)
        XCTAssertEqual(model.filter, "device")
    }

    func testCommandsCannotActOnHiddenLibrarySelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        let result = try await XCTUnwrap(model.store).importBook(from: fixture)
        await model.reload()
        model.selection = result.book.id
        XCTAssertEqual(model.commandSelection?.id, result.book.id)
        model.filter = "device"
        XCTAssertNil(model.commandSelection)
        model.filter = "MOBI"
        XCTAssertNil(model.commandSelection)
        model.filter = "all"
        model.search = "no matching book"
        XCTAssertNil(model.commandSelection)
    }
}
