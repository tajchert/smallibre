import XCTest
import CryptoKit
@testable import SmallibreCore

final class KindleFontFallbackTests: XCTestCase, @unchecked Sendable {
    private func fixture(encryptedPath: String = "Book/font.otf", algorithm: String = "http://www.idpf.org/2008/embedding") throws -> Data {
        let url = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let archive = try ZIPArchive(data: Data(contentsOf: url))
        let opf = String(decoding: try archive.data(named: "Book/package.opf"), as: UTF8.self)
            .replacingOccurrences(of: "</manifest>", with: "<item id=\"font\" href=\"font.otf\" media-type=\"application/vnd.ms-opentype\"/></manifest>")
        let html = String(decoding: try archive.data(named: "Book/text/one.xhtml"), as: UTF8.self)
            .replacingOccurrences(of: "</head>", with: "<style>@font-face { font-family: Custom; src: url('../font.otf'); } @page { margin: 24px; } p { font-family: Custom, serif; font-weight: bold; font-style: italic; }</style></head>")
        let encryption = "<encryption xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><EncryptedData xmlns=\"http://www.w3.org/2001/04/xmlenc#\"><EncryptionMethod Algorithm=\"\(algorithm)\"/><CipherData><CipherReference URI=\"\(encryptedPath)\"/></CipherData></EncryptedData></encryption>"
        return try archive.writing(replacements: ["Book/package.opf": Data(opf.utf8), "Book/text/one.xhtml": Data(html.utf8), "Book/font.otf": Data("authored-font-placeholder".utf8), "META-INF/encryption.xml": Data(encryption.utf8)])
    }
    func testFontOnlyObfuscationUsesFallbackAndWarnings() throws {
        let input = try fixture(), result = try AZW3Converter.convert(input)
        try AZW3Converter.validate(result.data)
        XCTAssertNil(result.data.range(of: Data("authored-font-placeholder".utf8)))
        XCTAssertNil(result.data.range(of: Data("@font-face".utf8)))
        XCTAssertNil(result.data.range(of: Data("@page".utf8)))
        XCTAssertNotNil(result.data.range(of: Data("font-weight: bold".utf8)))
        XCTAssertNotNil(result.data.range(of: Data("font-style: italic".utf8)))
        XCTAssertTrue(result.warnings.contains { $0.localizedCaseInsensitiveContains("font") })
        XCTAssertTrue(result.warnings.contains { $0.localizedCaseInsensitiveContains("margin") })
    }
    func testEncryptionOfContentCannotBeDisguisedAsFontObfuscation() throws {
        XCTAssertThrowsError(try AZW3Converter.convert(fixture(encryptedPath: "Book/text/one.xhtml")))
        XCTAssertThrowsError(try AZW3Converter.convert(fixture(encryptedPath: "Book/missing.otf")))
        XCTAssertThrowsError(try AZW3Converter.convert(fixture(algorithm: "http://www.w3.org/2001/04/xmlenc#aes128-cbc")))
    }
    func testAdobeFontFallbackAndUnsafeReferences() throws {
        _ = try AZW3Converter.convert(fixture(algorithm: "http://ns.adobe.com/pdf/enc#RC"))
        for path in ["../font.otf", "https://example.com/font.otf", "Book/font.otf#fragment"] {
            XCTAssertThrowsError(try AZW3Converter.convert(fixture(encryptedPath: path)))
        }
    }
    func testSavedTypographyAndMetadataUseArtifactWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root), source = root.appendingPathComponent("authored.epub")
        let input = try fixture(); try input.write(to: source)
        var book = try await store.importBook(from: source).book
        book.metadata.title = "Font fallback with saved edits"
        book.typography = TypographySettings(enabled: true, font: .serif, lineHeight: 1.8, marginPercent: 5)
        try await store.update(book)
        let artifact = try await store.prepareKindleArtifact(for: book.id)
        XCTAssertEqual(artifact.provenance.converterVersion, "2")
        XCTAssertEqual(try MOBIBook.inspect(artifact.verifiedData()).title, book.metadata.title)
        XCTAssertEqual(try Data(contentsOf: source), input)
        XCTAssertTrue(artifact.warnings.contains { $0.contains("fonts") })
    }
    func testVersionOneArtifactsStillValidate() throws {
        let source = Bundle.module.url(forResource: "kindle-prototype", withExtension: "epub", subdirectory: "Fixtures")!
        let input = try Data(contentsOf: source)
        var output = try AZW3Converter.convert(input).data
        var name = Data([0x6b,0xa7,0xb8,0x11,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8])
        name.append(Data(("urn:smallibre:azw3:" + AZW3Converter.profile + ":1:sha256:" + SHA256Digest.digest(input).value).utf8))
        var digest = Array(Insecure.SHA1.hash(data: name).prefix(16))
        digest[6] = (digest[6] & 15) | 80; digest[8] = (digest[8] & 63) | 128
        let hex = digest.map { String(format: "%02x", $0) }
        let uuid = [hex[0..<4],hex[4..<6],hex[6..<8],hex[8..<10],hex[10..<16]].map { $0.joined() }.joined(separator: "-")
        let start = Int(output.be32(78)) + 280
        var cursor = start + 12
        for _ in 0..<Int(output.be32(start + 8)) {
            let length = Int(output.be32(cursor + 4))
            if output.be32(cursor) == 113 { output.replaceSubrange(cursor + 8..<cursor + length, with: Data(uuid.utf8)) }
            cursor += length
        }
        try AZW3Converter.validate(output)
    }
    func testAmbiguousFontPathsAndHiddenEncryptionAreRejected() throws {
        let archive = try ZIPArchive(data: fixture())
        let opf = String(decoding: try archive.data(named: "Book/package.opf"), as: UTF8.self)
        let ambiguous = opf.replacingOccurrences(of: "</manifest>", with: "<item id=\"alias\" href=\"font.otf\" media-type=\"text/css\"/></manifest>")
        XCTAssertThrowsError(try AZW3Converter.convert(archive.writing(replacements: ["Book/package.opf": Data(ambiguous.utf8)])))
        let encryption = String(decoding: try archive.data(named: "META-INF/encryption.xml"), as: UTF8.self)
        let hidden = encryption.replacingOccurrences(of: "</EncryptedData>", with: "<CipherData><CipherValue>hidden</CipherValue></CipherData></EncryptedData>")
        XCTAssertThrowsError(try AZW3Converter.convert(archive.writing(replacements: ["META-INF/encryption.xml": Data(hidden.utf8)])))
    }
    func testExplicitExternalEPUBWithFontFallback() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let source = env["SMALLIBRE_TEST_FONT_EPUB"], let destination = env["SMALLIBRE_TEST_FONT_OUTPUT"] else {
            throw XCTSkip("Opt in with a local EPUB and a new local AZW3 output path")
        }
        let sourceURL = URL(fileURLWithPath: source), destinationURL = URL(fileURLWithPath: destination)
        guard !destinationURL.path.hasPrefix("/Volumes/"), !FileManager.default.fileExists(atPath: destination) else {
            throw BookError.invalid("Choose a new local output file.")
        }
        let original = try Data(contentsOf: sourceURL), result = try AZW3Converter.convert(original)
        try result.data.write(to: destinationURL, options: .withoutOverwriting)
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        print("Converted external EPUB: \(result.data.count) bytes; warnings: \(result.warnings.joined(separator: "; "))")
    }
}
