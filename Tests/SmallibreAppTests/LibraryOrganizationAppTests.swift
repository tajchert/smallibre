import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class LibraryOrganizationAppTests: XCTestCase {
    func book(_ title: String, series: String = "", number: Double? = nil) -> LibraryBook {
        LibraryBook(id: UUID(), metadata: BookMetadata(title: title, authors: ["Author"], language: "en", identifier: "", publisher: "", description: "", format: "EPUB", cover: nil), addedAt: Date(), byteCount: 1, originalFilename: title, hash: title, typography: .init(), organization: .init(series: series, seriesNumber: number))
    }
    func testSeriesSortUsesNumbersAndPlacesUnassignedBooksLast() {
        let model = AppModel(initialize: false)
        model.books = [book("Ten", series: "Stories", number: 10), book("No series"), book("Two", series: "Stories", number: 2)]
        model.sort = .series
        XCTAssertEqual(model.visibleBooks.map(\.metadata.title), ["Two", "Ten", "No series"])
    }
    func testMultiSelectionHasNoSingleBookActionsAndExcludesHiddenBooks() {
        let model = AppModel(initialize: false)
        model.books = [book("One"), book("Two")]
        model.librarySelection = Set(model.books.map(\.id))
        XCTAssertNil(model.selected)
        XCTAssertEqual(model.selectedLibraryBooks.count, 2)
        model.search = "One"
        XCTAssertEqual(model.selectedLibraryBooks.map(\.metadata.title), ["One"])
        model.filter = "device"
        XCTAssertTrue(model.selectedLibraryBooks.isEmpty)
    }
    func testListSelectionResetsGridRangeAnchor() {
        let model = AppModel(initialize: false)
        model.books = [book("A"), book("B"), book("C"), book("D")]; model.sort = .title
        model.selectLibraryBook(model.books[0].id)
        model.librarySelection = [model.books[2].id]
        model.selectLibraryBook(model.books[3].id, extending: true)
        XCTAssertEqual(model.librarySelection, [model.books[2].id, model.books[3].id])
    }
    func testEditorReceivesValidationErrorWithoutGlobalAlert() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(rootOverride: root)
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/SmallibreCoreTests/Fixtures/Small Hours.epub")
        var book = try await XCTUnwrap(model.store).importBook(from: fixture).book
        book.organization = .init(series: "Stories", seriesNumber: -1)
        let message = await model.save(book, reportError: false)
        XCTAssertNotNil(message)
        XCTAssertNil(model.error)
    }
    func testGridRangeSelectionAndCommandToggle() {
        let model = AppModel(initialize: false)
        model.books = [book("A"), book("B"), book("C")]; model.sort = .title
        model.selectLibraryBook(model.books[0].id)
        model.selectLibraryBook(model.books[2].id, extending: true)
        XCTAssertEqual(model.librarySelection.count, 3)
        model.selectLibraryBook(model.books[1].id, toggling: true)
        XCTAssertEqual(model.librarySelection, [model.books[0].id, model.books[2].id])
    }
}
