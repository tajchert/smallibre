import XCTest
@testable import SmallibreApp
@testable import SmallibreCore

@MainActor final class ReaderSortTests: XCTestCase {
    func testDeviceSortChangesOrderWithoutChangingSelection() {
        let reader = ReaderModel()
        let metadata = BookMetadata(title: "Zulu", authors: ["Alpha Author"], language: "", identifier: "", publisher: "", description: "", format: "MOBI", cover: nil)
        var older = ReaderBook(connection: reader.generation, relativePath: "Zulu.mobi", metadata: metadata, hash: "old", byteCount: 1, issue: nil)
        older.addedAt = Date(timeIntervalSince1970: 100)
        var newer = ReaderBook(connection: reader.generation, relativePath: "Alpha.kfx", metadata: nil, hash: "new", byteCount: 1, issue: nil)
        newer.addedAt = Date(timeIntervalSince1970: 200)
        reader.books = [older, newer]; reader.selectedIDs = [older.id]
        XCTAssertEqual(reader.visibleBooks(search: "", sort: .recent).map(\.id), [newer.id, older.id])
        XCTAssertEqual(reader.visibleBooks(search: "", sort: .title).map(\.id), [newer.id, older.id])
        XCTAssertEqual(reader.visibleBooks(search: "", sort: .author).map(\.id), [older.id, newer.id])
        XCTAssertEqual(reader.visibleBooks(search: "Zulu", sort: .title).map(\.id), [older.id])
        let model = AppModel(initialize: false)
        for sort in AppModel.Sort.allCases {
            if model.sort != sort { model.selectSort(sort) }
            let normal = reader.visibleBooks(search: "", sort: model.sort)
            model.selectSort(sort)
            XCTAssertEqual(reader.visibleBooks(search: "", sort: model.sort, reversed: model.sortReversed).map(\.id), normal.reversed().map(\.id))
            model.selectSort(sort)
            XCTAssertEqual(reader.visibleBooks(search: "", sort: model.sort, reversed: model.sortReversed).map(\.id), normal.map(\.id))
        }
        model.selectSort(.author)
        model.selectSort(.recent)
        XCTAssertFalse(model.sortReversed)
        XCTAssertEqual(reader.selectedIDs, [older.id])
    }

    func testScanProvidesDateEvenWhenReusingLegacyCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("example.kfx")
        try Data("minimal unsupported file".utf8).write(to: file)
        let expected = try XCTUnwrap(file.resourceValues(forKeys: [.creationDateKey]).creationDate)
        let cache = root.appendingPathComponent("cache.json")
        let reader = ReaderStore(root: root)
        let first = try await reader.scan(cacheURL: cache)
        XCTAssertEqual(try XCTUnwrap(first.first?.addedAt).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: [String: Any]])
        var entry = try XCTUnwrap(json["example.kfx"])
        var book = try XCTUnwrap(entry["book"] as? [String: Any]); book.removeValue(forKey: "addedAt")
        entry["book"] = book; json["example.kfx"] = entry
        try JSONSerialization.data(withJSONObject: json).write(to: cache)
        let second = try await reader.scan(cacheURL: cache)
        XCTAssertNotNil(second.first?.addedAt)
        let reused = await reader.cachedCount
        XCTAssertEqual(reused, 1)
    }
}
