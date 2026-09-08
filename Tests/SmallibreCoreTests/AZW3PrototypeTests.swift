import XCTest
@testable import SmallibreCore

final class AZW3PrototypeTests: XCTestCase {
    func testAuthoredEPUBProducesDeterministicStandaloneKF8() throws {
        let source = try fixture()
        let output = try AZW3PrototypeWriter.convert(source)
        XCTAssertEqual(output, try AZW3PrototypeWriter.convert(source))
        XCTAssertEqual(output.subdata(in: 60..<68), Data("BOOKMOBI".utf8))
        let metadata = try MOBIBook.inspect(output)
        XCTAssertEqual(metadata.format, "AZW3")
        XCTAssertEqual(metadata.title, "Smallibre native Kindle proof")
        XCTAssertEqual(metadata.authors, ["Smallibre contributors"])
        XCTAssertEqual(metadata.language, "en")
        let record0 = Int(output.be32(78))
        XCTAssertEqual(output.be16(record0), 1, "Prototype uses uncompressed text")
        XCTAssertEqual(output.be32(record0 + 36), 8)
        let textRecords = Int(output.be16(record0 + 8))
        let firstText = Int(output.be32(86))
        let afterText = Int(output.be32(78 + (textRecords + 1) * 8))
        let raw = try XCTUnwrap(String(data: output.subdata(in: firstText..<afterText), encoding: .utf8))
        XCTAssertTrue(raw.contains("Zażółć gęślą jaźń — café 日本語 🌙."))
        XCTAssertTrue(raw.contains("kindle:embed:0001?mime=image/png"))
        XCTAssertFalse(raw.contains("two.xhtml#note"))
        XCTAssertTrue(raw.contains("kindle:pos:fid:0001:off:"))
        XCTAssertNotNil(output.range(of: Data("INDX".utf8)))
        XCTAssertNotNil(output.range(of: Data("FDST".utf8)))
    }

    func testPrototypeRejectsContentItCannotPreserve() throws {
        let source = try fixture()
        let archive = try ZIPArchive(data: source)
        let path = "Book/text/one.xhtml"
        let original = try XCTUnwrap(String(data: archive.data(named: path), encoding: .utf8))
        for addition in ["<script>alert(1)</script>", "<style>p { color: red }</style>",
                         "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>x</text></svg>",
                         "<img src=\"https://example.com/image.png\"/>", "<a href=\"two.xhtml#missing\">bad</a>"] {
            let changed = original.replacingOccurrences(of: "</body>", with: addition + "</body>")
            let book = try archive.writing(replacements: [path: Data(changed.utf8)])
            XCTAssertThrowsError(try AZW3PrototypeWriter.convert(book), addition)
        }
    }

    func testPrototypeHandlesMultibyteTextAcross4096ByteRecords() throws {
        let archive = try ZIPArchive(data: fixture())
        let path = "Book/text/one.xhtml"
        let original = try XCTUnwrap(String(data: archive.data(named: path), encoding: .utf8))
        let text = String(repeating: "café 🌙 日本語 ", count: 240)
        let changed = original.replacingOccurrences(of: "</body>", with: "<p>" + text + "</p></body>")
        let output = try AZW3PrototypeWriter.convert(archive.writing(replacements: [path: Data(changed.utf8)]))
        let record0 = Int(output.be32(78)), count = Int(output.be16(Int(output.be32(78)) + 8))
        XCTAssertGreaterThan(count, 1)
        let begin = Int(output.be32(86)), end = Int(output.be32(78 + (count + 1) * 8))
        let raw = output.subdata(in: begin..<end)
        XCTAssertEqual(raw.count, Int(output.be32(record0 + 4)))
        XCTAssertTrue(try XCTUnwrap(String(data: raw, encoding: .utf8)).contains(text))
    }

    func testLiteralKindlePositionTextIsNotRewrittenAsALink() throws {
        let archive = try ZIPArchive(data: fixture()), path = "Book/text/one.xhtml"
        let original = String(data: try archive.data(named: path), encoding: .utf8)!
        let literal = "Literal: kindle:pos:fid:0000:off:0000000000 is text."
        let changed = original.replacingOccurrences(of: "</body>", with: "<p>" + literal + "</p></body>")
        let document = try AZW3PrototypeDocument(archive.writing(replacements: [path: Data(changed.utf8)]))
        XCTAssertTrue(document.chapters[0].body.contains(literal))
    }

    func testPrototypeRejectsDroppedRootAndVoidContent() throws {
        let archive = try ZIPArchive(data: fixture()), path = "Book/text/one.xhtml"
        let original = String(data: try archive.data(named: path), encoding: .utf8)!
        for changed in [
            original.replacingOccurrences(of: "<html ", with: "<html dir=\"rtl\" "),
            original.replacingOccurrences(of: "</body>", with: "<br>Meaningful content</br></body>"),
            original.replacingOccurrences(of: "</body>", with: "</body><body><p>Lost chapter content</p></body>"),
            original.replacingOccurrences(of: "</html>", with: "<script>scripted()</script></html>")
        ] {
            XCTAssertThrowsError(try AZW3PrototypeWriter.convert(archive.writing(replacements: [path: Data(changed.utf8)])))
        }
    }

    func testAuxiliaryRecordsDescribeTheEncodedText() throws {
        let output = try AZW3PrototypeWriter.convert(fixture())
        let header = Int(output.be32(78))
        let fcisRecord = Int(output.be32(header + 200))
        let fcis = Int(output.be32(78 + fcisRecord * 8))
        XCTAssertEqual(output.subdata(in: fcis..<fcis + 4), Data("FCIS".utf8))
        XCTAssertEqual(output.be32(fcis + 20), output.be32(header + 4))
        XCTAssertEqual(output.be32(fcis + 40), 8)
        XCTAssertEqual(output.be16(fcis + 44), 1)
        XCTAssertEqual(output.be16(fcis + 46), 1)
    }

    func testWriteOptInPrototypeForIndependentDecoder() throws {
        guard let path = ProcessInfo.processInfo.environment["SMALLIBRE_AZW3_PROTOTYPE_OUTPUT"] else {
            throw XCTSkip("Set SMALLIBRE_AZW3_PROTOTYPE_OUTPUT to retain an authored prototype for independent decoding")
        }
        let bytes = try AZW3PrototypeWriter.convert(fixture())
        try bytes.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
    }

    private func fixture() throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!)
    }
}
