import XCTest
@testable import SmallibreCore

final class MOBIEditorTests: XCTestCase {
    func testMetadataGrowthPreservesFollowingRecordBytes() throws {
        let url = Bundle.module.url(forResource: "minimal", withExtension: "mobi", subdirectory: "Fixtures")!
        var original = try Data(contentsOf: url)
        let offset = Int(original.be32(78))
        let record = original.subdata(in: offset..<original.count)
        original = original.prefix(offset)
        original.replaceSubrange(76..<78, with: [0, 2])
        original.replaceSubrange(78..<82, with: big(offset + 8))
        var entry = Data(big(offset + 8 + record.count)); entry.append(contentsOf: [0,0,0,2])
        original.insert(contentsOf: entry, at: 86)
        original.append(record); original.append(Data("unaltered text and image record".utf8))
        var metadata = try MOBIBook.inspect(original)
        metadata.title = "A much longer title — with Polish łódź"
        metadata.authors = ["First Author", "Second Author"]
        metadata.publisher = "Smallibre Test Editions"
        let edited = try MOBIMetadataEditor.prepare(original, metadata: metadata)
        let parsed = try MOBIBook.inspect(edited)
        XCTAssertEqual(parsed.title, metadata.title); XCTAssertEqual(parsed.authors, metadata.authors)
        XCTAssertEqual(parsed.publisher, metadata.publisher)
        XCTAssertEqual(edited.subdata(in: Int(edited.be32(86))..<edited.count), original.subdata(in: Int(original.be32(86))..<original.count))
    }
    func testProtectedBookIsNeverRewritten() throws {
        let url = Bundle.module.url(forResource: "minimal", withExtension: "mobi", subdirectory: "Fixtures")!
        var data = try Data(contentsOf: url)
        let metadata = try MOBIBook.inspect(data)
        let offset = Int(data.be32(78)); data[offset + 13] = 2
        XCTAssertThrowsError(try MOBIMetadataEditor.prepare(data, metadata: metadata))
        XCTAssertEqual(try MOBIBook.inspect(data, allowProtected: true).title, metadata.title)
    }
    func testHybridMOBIIsRejected() throws {
        let url = Bundle.module.url(forResource: "minimal", withExtension: "mobi", subdirectory: "Fixtures")!
        var data = try Data(contentsOf: url)
        let metadata = try MOBIBook.inspect(data), offset = Int(data.be32(78))
        let start = offset + 16 + Int(data.be32(offset + 20))
        let length = Int(data.be32(start + 4)), count = Int(data.be32(start + 8)), title = Int(data.be32(offset + 84))
        data.insert(contentsOf: big(121) + big(12) + big(1), at: start + 12)
        data.replaceSubrange(start + 4..<start + 8, with: big(length + 12))
        data.replaceSubrange(start + 8..<start + 12, with: big(count + 1))
        data.replaceSubrange(offset + 84..<offset + 88, with: big(title + 12))
        XCTAssertThrowsError(try MOBIMetadataEditor.prepare(data, metadata: metadata))
    }
    private func big(_ number: Int) -> [UInt8] { [UInt8((number >> 24) & 255), UInt8((number >> 16) & 255), UInt8((number >> 8) & 255), UInt8(number & 255)] }
}
