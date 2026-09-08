import XCTest
@testable import SmallibreCore

final class AZW3ValidatorTests: XCTestCase {
    private func fixture() throws -> Data {
        let epub = try Data(contentsOf: Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!)
        return try AZW3Converter.convert(epub).data
    }
    /// Locate fields from the Palm record directory and INDX entry directory, independently of the writer.
    private func valueOffsets(_ bytes: Data, pointer: Int) -> [Int] {
        let header = Int(bytes.be32(78)), index = Int(bytes.be32(header + pointer))
        let block = Int(bytes.be32(78 + (index + 1) * 8)), table = block + Int(bytes.be32(block + 20))
        let entry = block + Int(bytes.be16(table + 4))
        var cursor = entry + 1 + Int(bytes[entry]) + 1, result: [Int] = []
        let end = table
        while cursor < end && bytes[cursor] != 0 {
            result.append(cursor)
            repeat { let byte = bytes[cursor]; cursor += 1; if byte & 128 != 0 { break } } while cursor < end
            if result.count == (pointer == 248 ? 5 : 6) { break }
        }
        return result
    }
    func testRejectsChangedFragmentLengthAndNavigationDestination() throws {
        let original = try fixture()
        for pointer in [248, 244, 252] {
            var corrupt = original
            let starts = valueOffsets(corrupt, pointer: pointer)
            XCTAssertEqual(starts.count, pointer == 248 ? 5 : 6)
            // Change a decoded value without changing byte lengths, record starts or INDX tables.
            let target = starts.last!
            corrupt[target] ^= 1
            XCTAssertThrowsError(try AZW3Converter.validate(corrupt), "Pointer \(pointer) corrupt relationship")
        }
    }
    func testRejectsUnterminatedVariableIntegerAndChangedControl() throws {
        let original = try fixture(), starts = valueOffsets(original, pointer: 248)
        var variable = original
        for offset in starts.last!..<starts.last! + 5 { variable[offset] = 0x7f }
        XCTAssertThrowsError(try AZW3Converter.validate(variable))
        var control = original
        control[starts[0] - 1] = 0
        XCTAssertThrowsError(try AZW3Converter.validate(control))
    }
    func testRejectsInvalidDocumentIdentityAndAuxiliaryPointer() throws {
        let original = try fixture(), header = Int(original.be32(78))
        var cursor = header + 292, identity = original
        for _ in 0..<Int(original.be32(header + 288)) {
            if original.be32(cursor) == 113 { identity[cursor + 8] = identity[cursor + 8] == 0x61 ? 0x62 : 0x61; break }
            cursor += Int(original.be32(cursor + 4))
        }
        XCTAssertThrowsError(try AZW3Converter.validate(identity))
        var auxiliary = original
        auxiliary[header + 203] ^= 1
        XCTAssertThrowsError(try AZW3Converter.validate(auxiliary))
    }
    func testRejectsInvalidEmbeddedImageAndInternalLinkReferences() throws {
        let original = try fixture()
        for token in ["kindle:embed:", "kindle:pos:fid:"] {
            var corrupt = original
            let range = try XCTUnwrap(corrupt.range(of: Data(token.utf8)))
            // Keep text byte count and record boundaries intact while selecting a nonexistent object.
            corrupt.replaceSubrange(range.upperBound..<range.upperBound + 4, with: Data("VVVV".utf8))
            XCTAssertThrowsError(try AZW3Converter.validate(corrupt))
        }
        var image = original
        let header = Int(image.be32(78)), resource = Int(image.be32(header + 108))
        let imageOffset = Int(image.be32(78 + resource * 8))
        image[imageOffset] = 0
        XCTAssertThrowsError(try AZW3Converter.validate(image))
    }
    func testRejectsMalformedEntryDirectoryWithoutTrap() throws {
        let original = try fixture(), header = Int(original.be32(78))
        let index = Int(original.be32(header + 248)), block = Int(original.be32(78 + (index + 1) * 8))
        let table = block + Int(original.be32(block + 20))
        var corrupt = original
        corrupt[table + 4] = 0xff; corrupt[table + 5] = 0xff
        XCTAssertThrowsError(try AZW3Converter.validate(corrupt))
    }
}
